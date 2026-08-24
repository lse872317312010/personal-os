import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/composition/native_sqlcipher_event_store.dart';
import 'package:personal_os_app/src/composition/native_sqlcipher_session_coordinator.dart';
import 'package:personal_os_device_security/device_security.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_security_api/security_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

void main() {
  const channel = MethodChannel('test/personal_os/native_event_store');
  late List<MethodCall> calls;
  late String storedJson;

  setUp(() {
    calls = <MethodCall>[];
    storedJson = '';
  });

  tearDown(() {
    _setChannelHandler(channel, null);
  });

  test('appendAll is one strict JSON batch and reads complete envelopes', () async {
    final store = NativeSqlCipherEventStore(channel: channel);
    store.attachNativeSession(PlatformVaultSession(id: 'native-session'));
    final event = _event();
    storedJson = EventEnvelopeJsonCodec.encodeString(event);
    _setChannelHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'appendEvents') {
        return null;
      }
      if (call.method == 'readEventById') {
        return <String, Object?>{
          'eventId': 'event-1',
          'eventJson': storedJson,
        };
      }
      if (call.method == 'readEventsByProfile' ||
          call.method == 'readEventsBySubject') {
        return <Object?>[
          <String, Object?>{
            'eventId': 'event-1',
            'eventJson': storedJson,
          },
        ];
      }
      return null;
    });

    await store.appendAll(<EventEnvelope>[event]);
    final byProfile = await store.readBySubject(
      ObjectRef(type: 'profile', id: EntityId('profile-1')),
    );
    final byObservation = await store.readBySubject(
      ObjectRef(type: 'observation', id: EntityId('observation-1')),
    );
    final byId = await store.readById(event.eventId);

    expect(calls.where((call) => call.method == 'appendEvents'), hasLength(1));
    final append = calls.singleWhere((call) => call.method == 'appendEvents');
    final arguments = append.arguments as Map<Object?, Object?>;
    expect(arguments['sessionId'], 'native-session');
    final batch = arguments['events'] as List<Object?>;
    expect(batch, hasLength(1));
    final record = batch.single as Map<Object?, Object?>;
    expect(record['eventJson'], storedJson);
    expect(record['eventId'], event.eventId);
    expect(record['profileId'], 'profile-1');
    expect(byProfile.single.eventId, event.eventId);
    expect(byObservation.single.eventId, event.eventId);
    expect(byId?.eventId, event.eventId);
  });

  test(
      'readBySubject matches type and id regardless of revision and filters limit in Dart',
      () async {
    final store = NativeSqlCipherEventStore(channel: channel);
    store.attachNativeSession(PlatformVaultSession(id: 'native-session'));
    final unrelated = _event(
      id: 'event-unrelated',
      observationId: 'observation-2',
      observationRevision: 1,
    );
    final matching = _event(id: 'event-matching', observationRevision: 2);
    _setChannelHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'readEventsBySubject') {
        final arguments = call.arguments as Map<Object?, Object?>;
        expect(arguments['limit'], 1000);
        return <Object?>[
          <String, Object?>{
            'eventId': unrelated.eventId,
            'eventJson': EventEnvelopeJsonCodec.encodeString(unrelated),
          },
          <String, Object?>{
            'eventId': matching.eventId,
            'eventJson': EventEnvelopeJsonCodec.encodeString(matching),
          },
        ];
      }
      return null;
    });

    final events = await store.readBySubject(
      ObjectRef(
        type: 'observation',
        id: EntityId('observation-1'),
        revision: Revision(99),
      ),
      limit: 1,
    );

    expect(events.map((event) => event.eventId), ['event-matching']);
  });

  test('D4, malformed JSON, and unknown fields fail closed', () async {
    final store = NativeSqlCipherEventStore(channel: channel);
    store.attachNativeSession(PlatformVaultSession(id: 'native-session'));
    var channelCalls = 0;
    _setChannelHandler(channel, (call) async {
      channelCalls += 1;
      if (call.method == 'appendEvents') return null;
      return <Object?>[
        <String, Object?>{
          'eventJson': '{"schema_version":1,"future":true}',
          'eventId': 'event-1',
        },
      ];
    });

    await expectLater(
      store.appendAll(
        <EventEnvelope>[_event(id: 'event-d4', sensitivity: Sensitivity.d4)],
      ),
      throwsA(isA<PersistenceException>().having(
        (error) => error.code,
        'code',
        PersistenceErrorCode.d4PersistenceForbidden,
      )),
    );
    expect(channelCalls, 0);
    await expectLater(
      store.readBySubject(
        ObjectRef(type: 'profile', id: EntityId('profile-1')),
      ),
      throwsA(isA<PersistenceException>().having(
        (error) => error.code,
        'code',
        PersistenceErrorCode.schemaViolation,
      )),
    );

    _setChannelHandler(channel, (call) async => <Object?>[
          <String, Object?>{
            'eventId': 'event-1',
            'eventJson': 'not-json',
          },
        ]);
    await expectLater(
      store.readBySubject(
        ObjectRef(type: 'profile', id: EntityId('profile-1')),
      ),
      throwsA(isA<PersistenceException>()),
    );
  });

  test('native failures expose only stable PersistenceException identity',
      () async {
    final store = NativeSqlCipherEventStore(channel: channel);
    store.attachNativeSession(PlatformVaultSession(id: 'native-session'));
    _setChannelHandler(channel, (_) async {
      throw PlatformException(
        code: 'security.provider_unavailable',
        message: 'raw SQLCipher path and exception',
      );
    });

    try {
      await store.appendAll(<EventEnvelope>[_event()]);
      fail('expected PersistenceException');
    } on PersistenceException catch (error) {
      expect(error.toString(), 'PersistenceException(${error.code})');
      expect(error.toString(), isNot(contains('raw SQLCipher')));
    }
  });

  test('native event conflicts map to a stable redacted batch failure',
      () async {
    final store = NativeSqlCipherEventStore(channel: channel);
    store.attachNativeSession(PlatformVaultSession(id: 'native-session'));
    _setChannelHandler(channel, (call) async {
      if (call.method == 'appendEvents') {
        throw PlatformException(
          code: 'security.vault_event_conflict',
          message: 'event id and SQLCipher details must not cross the boundary',
        );
      }
      return null;
    });

    try {
      await store.appendAll(<EventEnvelope>[
        _event(id: 'event-1'),
        _event(id: 'event-2'),
      ]);
      fail('expected PersistenceException');
    } on PersistenceException catch (error) {
      expect(error.code, PersistenceErrorCode.eventConflict);
      expect(error.message, 'event_conflict');
      expect(error.toString(), 'PersistenceException(${error.code})');
      expect(error.toString(), isNot(contains('event id')));
      expect(error.toString(), isNot(contains('SQLCipher')));
    }
  });

  test('batch encoding preserves stable PersistenceException failures',
      () async {
    final store = NativeSqlCipherEventStore(channel: channel);
    store.attachNativeSession(PlatformVaultSession(id: 'native-session'));

    try {
      await store.appendAll(<EventEnvelope>[_eventWithoutProfile()]);
      fail('expected PersistenceException');
    } on PersistenceException catch (error) {
      expect(error.code, PersistenceErrorCode.eventConflict);
      expect(error.message, 'missing_subject');
      expect(error.toString(), 'PersistenceException(${error.code})');
    }
  });

  test('coordinator binds and closes the exact native session used by store',
      () async {
    final bridge = _FakePlatformBridge();
    final store = NativeSqlCipherEventStore(channel: channel);
    final coordinator = NativeSqlCipherSessionCoordinator(
      bridge: bridge,
      eventStore: store,
    );
    _setChannelHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'appendEvents') return null;
      return null;
    });

    final session = await coordinator.open(
      grant: UnlockGrant.opaque(
        id: 'ticket-1',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      ),
    );
    await store.appendAll(<EventEnvelope>[_event()]);
    await coordinator.close(session);

    final append = calls.singleWhere((call) => call.method == 'appendEvents');
    expect((append.arguments as Map<Object?, Object?>)['sessionId'],
        bridge.openedSessionId);
    expect(bridge.closedSessionId, bridge.openedSessionId);
    await expectLater(
      store.appendAll(<EventEnvelope>[_event(id: 'after-close')]),
      throwsA(isA<PersistenceException>()),
    );
  });
}

void _setChannelHandler(
  MethodChannel channel,
  Future<Object?> Function(MethodCall)? handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, handler);
}

EventEnvelope _event({
  String id = 'event-1',
  Sensitivity sensitivity = Sensitivity.d3,
  String observationId = 'observation-1',
  int? observationRevision,
}) => EventEnvelope(
      eventId: id,
      eventType: EventTypes.observationRecorded,
      eventVersion: 1,
      occurredAt: DateTime.utc(2026, 8, 17, 10),
      recordedAt: DateTime.utc(2026, 8, 17, 10, 1),
      actor: ActorRef(
        actorId: 'user-1',
        actorType: ActorType.user,
        authoritySource: 'local-session',
      ),
      subjectRefs: <ObjectRef>[
        ObjectRef(
          type: 'observation',
          id: EntityId(observationId),
          revision: observationRevision == null
              ? null
              : Revision(observationRevision),
        ),
        ObjectRef(type: 'profile', id: EntityId('profile-1')),
      ],
      correlationId: 'correlation-1',
      sensitivity: sensitivity,
      payload: const <String, Object?>{'media_type': 'image/*'},
    );

EventEnvelope _eventWithoutProfile() => EventEnvelope(
      eventId: 'event-without-profile',
      eventType: EventTypes.observationRecorded,
      eventVersion: 1,
      occurredAt: DateTime.utc(2026, 8, 17, 10),
      recordedAt: DateTime.utc(2026, 8, 17, 10, 1),
      actor: ActorRef(
        actorId: 'user-1',
        actorType: ActorType.user,
        authoritySource: 'local-session',
      ),
      subjectRefs: <ObjectRef>[
        ObjectRef(type: 'observation', id: EntityId('observation-1')),
      ],
      correlationId: 'correlation-1',
      sensitivity: Sensitivity.d3,
      payload: const <String, Object?>{'media_type': 'image/*'},
    );

final class _FakePlatformBridge implements PlatformSecurityBridge {
  final openedSessionId = 'native-session-1';
  String? closedSessionId;

  @override
  Future<DeviceSecurityCapabilities> inspectCapabilities() async =>
      const DeviceSecurityCapabilities(
        protectionLevel: HardwareProtectionLevel.software,
        userAuthenticationAvailable: true,
        deviceCredentialAvailable: true,
        nonExportableKeys: true,
        atomicDeviceRevocation: false,
      );

  @override
  Future<PlatformAuthenticationTicket> authenticate(
    PlatformAuthenticationRequest request,
  ) async => PlatformAuthenticationTicket(
        id: 'ticket-1',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );

  @override
  Future<PlatformVaultSession> openVault({
    required String authenticationTicketId,
    required DateTime ticketExpiresAt,
  }) async => PlatformVaultSession(id: openedSessionId);

  @override
  Future<void> closeVault({required PlatformVaultSession session}) async {
    closedSessionId = session.id;
  }

  @override
  Future<PlatformKeyReference> createKey({
    required KeyPurpose purpose,
    required String authenticationTicketId,
  }) => _unsupported();

  @override
  Future<PlatformWrappedKey> wrapKey({
    required PlatformKeyReference key,
    required PlatformKeyReference wrappingKey,
    required String authenticationTicketId,
  }) => _unsupported();

  @override
  Future<PlatformKeyReference> unwrapKey({
    required PlatformWrappedKey wrappedKey,
    required PlatformKeyReference wrappingKey,
    required String authenticationTicketId,
  }) => _unsupported();

  @override
  Future<PlatformEpochRotation> rotateAccountEpoch({
    required PlatformKeyReference currentEpoch,
    required String authenticationTicketId,
  }) => _unsupported();

  @override
  Future<PlatformEpochRotation> revokeDeviceAndRotate({
    required String deviceId,
    required PlatformKeyReference currentEpoch,
    required String authenticationTicketId,
  }) => _unsupported();

  @override
  Future<void> authorizeNewData({
    required String deviceId,
    required PlatformKeyReference epochKey,
  }) => _unsupported();

  @override
  Future<void> destroyKey({
    required PlatformKeyReference key,
    required String authenticationTicketId,
  }) => _unsupported();

  Future<T> _unsupported<T>() => Future<T>.error(
        const PlatformSecurityFailure(PlatformSecurityFailureCode.unavailable),
      );
}

