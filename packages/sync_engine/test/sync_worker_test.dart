import 'dart:convert';
import 'dart:typed_data';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:personal_os_sync_api/sync_api.dart';
import 'package:personal_os_sync_engine/sync_engine.dart';
import 'package:test/test.dart';

void main() {
  group('push', () {
    test('strictly encodes a non-D4 batch and seals authenticated metadata', () async {
      final relay = _FakeTransport();
      final crypto = _FakeCrypto();
      final worker = _worker(relay: relay, crypto: crypto);
      final result = await worker.pushBatch(
        envelopeId: 'out-1',
        events: [_event('event-1')],
        sequence: DeviceSequenceRange(first: 0, last: 0),
        cursor: OpaqueSyncCursor.initial(),
      );

      expect(result.disposition, SyncDisposition.pushed);
      expect(relay.pushed.single.senderDeviceId, 'device-local');
      expect(relay.pushed.single.sequence.count, 1);
      final payload = jsonDecode(utf8.decode(crypto.lastPlaintext!)) as Map;
      expect(payload['payload_version'], 1);
      expect(payload['events'], hasLength(1));
      expect(utf8.decode(crypto.lastMetadata!), contains('out-1'));
      expect(crypto.sealInputReference, everyElement(0));
    });

    test('rejects mismatched acknowledgement and maps transport failures', () async {
      final relay = _FakeTransport()..acknowledgedIds = ['some-other-id'];
      final worker = _worker(relay: relay);
      final mismatch = await worker.pushBatch(
        envelopeId: 'out-1',
        events: [_event('event-1')],
        sequence: DeviceSequenceRange(first: 0, last: 0),
        cursor: OpaqueSyncCursor.initial(),
      );
      expect(mismatch.reasonCode, SyncFailureReason.relayAckMismatch);

      relay.throwOnPush = true;
      final failed = await worker.pushBatch(
        envelopeId: 'out-2',
        events: [_event('event-2')],
        sequence: DeviceSequenceRange(first: 1, last: 1),
        cursor: OpaqueSyncCursor.initial(),
      );
      expect(failed.reasonCode, SyncFailureReason.transportFailed);
    });

    test('D4 and sequence mismatch fail before crypto or transport', () async {
      final relay = _FakeTransport();
      final crypto = _FakeCrypto();
      final worker = _worker(relay: relay, crypto: crypto);
      final d4 = await worker.pushBatch(
        envelopeId: 'out-d4',
        events: [_event('secret', sensitivity: Sensitivity.d4)],
        sequence: DeviceSequenceRange(first: 0, last: 0),
        cursor: OpaqueSyncCursor.initial(),
      );
      final mismatch = await worker.pushBatch(
        envelopeId: 'out-count',
        events: [_event('event-1')],
        sequence: DeviceSequenceRange(first: 0, last: 1),
        cursor: OpaqueSyncCursor.initial(),
      );
      expect(d4.reasonCode, SyncFailureReason.d4SyncForbidden);
      expect(mismatch.reasonCode, SyncFailureReason.sequenceCountMismatch);
      expect(crypto.sealCalls, 0);
      expect(relay.pushed, isEmpty);
    });
  });

  group('pull', () {
    test('opens, strictly decodes, and atomically appends a valid batch', () async {
      final crypto = _FakeCrypto();
      final store = _RecordingStore();
      final relay = _FakeTransport()
        ..page = _page([
          _inbound(crypto, 'env-1', 0, [_event('event-1')]),
        ]);
      final worker = _worker(relay: relay, crypto: crypto, store: store);
      final page = await worker.pullPage(cursor: OpaqueSyncCursor.initial());

      expect(page.items.single.disposition, SyncDisposition.applied);
      expect(page.cursor, OpaqueSyncCursor('page-next'));
      expect(store.transactions, hasLength(1));
      expect(store.transactions.single.single.eventId, 'event-1');
      expect(worker.lastReceivedSequence('device-peer'), 0);
      expect(crypto.openOutputReference, everyElement(0));
      expect(store.transactions.single.single.payload['source_id'], 'source-1');
    });

    test('pull transport failure is stable and retains cursor', () async {
      final relay = _FakeTransport()..throwOnPull = true;
      final input = OpaqueSyncCursor.initial();
      final page = await _worker(relay: relay).pullPage(cursor: input);
      expect(page.items.single.reasonCode, SyncFailureReason.transportFailed);
      expect(page.cursor, input);
    });

    test('duplicate is stable and never decrypts or appends', () async {
      final crypto = _FakeCrypto();
      final store = _RecordingStore();
      final relay = _FakeTransport()
        ..page = _page([_inbound(crypto, 'old', 0, [_event('event-1')])]);
      final worker = _worker(
        relay: relay,
        crypto: crypto,
        store: store,
        lastReceived: {'device-peer': 0},
      );
      final result = (await worker.pullPage(cursor: OpaqueSyncCursor.initial()))
          .items
          .single;
      expect(result.disposition, SyncDisposition.duplicate);
      expect(crypto.openCalls, 0);
      expect(store.transactions, isEmpty);
    });

    test('gap, overlap, unknown sender, epoch, and protocol reject before write', () async {
      Future<String?> reasonFor(
        EncryptedSyncEnvelope envelope, {
        Map<String, int> lastReceived = const {},
      }) async {
        final relay = _FakeTransport()..page = _page([envelope]);
        final worker = _worker(relay: relay, lastReceived: lastReceived);
        return (await worker.pullPage(cursor: OpaqueSyncCursor.initial()))
            .items
            .single
            .reasonCode;
      }

      final crypto = _FakeCrypto();
      expect(
        await reasonFor(_inbound(crypto, 'gap', 2, [_event('e') ])),
        SyncFailureReason.sequenceGap,
      );
      expect(
        await reasonFor(
          _inboundRange(crypto, 'overlap', 1, 2, [_event('e1'), _event('e2')]),
          lastReceived: {'device-peer': 1},
        ),
        SyncFailureReason.sequenceOverlap,
      );
      expect(
        await reasonFor(_copy(_inbound(crypto, 'sender', 0, [_event('e')]), sender: 'stranger')),
        SyncFailureReason.unknownSender,
      );
      expect(
        await reasonFor(_copy(_inbound(crypto, 'epoch', 0, [_event('e')]), epoch: 'old')),
        SyncFailureReason.epochMismatch,
      );
      expect(
        await reasonFor(_copy(_inbound(crypto, 'version', 0, [_event('e')]), version: 2)),
        SyncFailureReason.unsupportedProtocolVersion,
      );
    });

    test('malformed or unknown payload version never partially writes', () async {
      for (final plaintext in [
        Uint8List.fromList(utf8.encode('{bad json')),
        Uint8List.fromList(utf8.encode('{"payload_version":2,"events":[]}')),
      ]) {
        final crypto = _FakeCrypto()..forcedOpen = plaintext;
        final store = _RecordingStore();
        final relay = _FakeTransport()
          ..page = _page([_inbound(crypto, 'bad', 0, [_event('unused')])]);
        final worker = _worker(relay: relay, crypto: crypto, store: store);
        final result = (await worker.pullPage(cursor: OpaqueSyncCursor.initial()))
            .items
            .single;
        expect(result.reasonCode, SyncFailureReason.payloadDecodeFailed);
        expect(store.transactions, isEmpty);
        expect(worker.lastReceivedSequence('device-peer'), -1);
      }
    });

    test('whole decoded batch is passed to one appendAll transaction', () async {
      final crypto = _FakeCrypto();
      final store = _RecordingStore()..fail = true;
      final relay = _FakeTransport()
        ..page = _page([
          _inboundRange(
            crypto,
            'two',
            0,
            1,
            [_event('event-1'), _event('event-2')],
          ),
        ]);
      final worker = _worker(relay: relay, crypto: crypto, store: store);
      final result = (await worker.pullPage(cursor: OpaqueSyncCursor.initial()))
          .items
          .single;
      expect(result.reasonCode, SyncFailureReason.appendFailed);
      expect(store.transactions, isEmpty);
      expect(worker.lastReceivedSequence('device-peer'), -1);
    });
  });
}

SyncWorker _worker({
  _FakeTransport? relay,
  _FakeCrypto? crypto,
  _RecordingStore? store,
  Map<String, int> lastReceived = const {},
}) =>
    SyncWorker(
      deviceId: 'device-local',
      accountPseudonym: 'account',
      recipientEpoch: 'epoch-1',
      trustedSenderDeviceIds: {'device-peer'},
      transport: relay ?? _FakeTransport(),
      cryptography: crypto ?? _FakeCrypto(),
      eventStore: store ?? _RecordingStore(),
      lastReceivedSequenceBySender: lastReceived,
    );

EventEnvelope _event(String id, {Sensitivity sensitivity = Sensitivity.d2}) =>
    EventEnvelope(
      eventId: id,
      eventType: 'SourceCaptured',
      eventVersion: 1,
      occurredAt: DateTime.utc(2026, 8, 20),
      recordedAt: DateTime.utc(2026, 8, 20),
      actor: ActorRef(
        actorId: 'user-1',
        actorType: ActorType.user,
        authoritySource: 'test',
      ),
      correlationId: 'correlation-1',
      sensitivity: sensitivity,
      payload: const {'source_id': 'source-1', 'expected_revision': 0},
    );

EncryptedSyncEnvelope _inbound(
  _FakeCrypto crypto,
  String id,
  int sequence,
  List<EventEnvelope> events,
) =>
    _inboundRange(crypto, id, sequence, sequence, events);

EncryptedSyncEnvelope _inboundRange(
  _FakeCrypto crypto,
  String id,
  int first,
  int last,
  List<EventEnvelope> events,
) {
  final plaintext = Uint8List.fromList(utf8.encode(jsonEncode({
    'payload_version': 1,
    'events': events.map(EventEnvelopeJsonCodec.encode).toList(),
  })));
  crypto.payloads[id] = plaintext;
  return EncryptedSyncEnvelope(
    protocolVersion: 1,
    envelopeId: id,
    accountPseudonym: 'account',
    senderDeviceId: 'device-peer',
    recipientEpoch: 'epoch-1',
    sequence: DeviceSequenceRange(first: first, last: last),
    ciphertext: Uint8List.fromList(utf8.encode(id)),
    signature: Uint8List.fromList([1]),
  );
}

EncryptedSyncEnvelope _copy(
  EncryptedSyncEnvelope source, {
  int? version,
  String? sender,
  String? epoch,
}) =>
    EncryptedSyncEnvelope(
      protocolVersion: version ?? source.protocolVersion,
      envelopeId: source.envelopeId,
      accountPseudonym: source.accountPseudonym,
      senderDeviceId: sender ?? source.senderDeviceId,
      recipientEpoch: epoch ?? source.recipientEpoch,
      sequence: source.sequence,
      ciphertext: source.ciphertext,
      signature: source.signature,
    );

SyncPage _page(List<EncryptedSyncEnvelope> envelopes) => SyncPage(
      envelopes: envelopes,
      cursor: OpaqueSyncCursor('page-next'),
      hasMore: false,
    );

final class _FakeTransport implements SyncPort {
  SyncPage page = SyncPage(
    envelopes: const [],
    cursor: OpaqueSyncCursor('page-next'),
    hasMore: false,
  );
  final List<EncryptedSyncEnvelope> pushed = [];
  List<String>? acknowledgedIds;
  bool throwOnPush = false;
  bool throwOnPull = false;

  @override
  Future<SyncPage> pull({required String deviceId, required OpaqueSyncCursor cursor, int limit = 100}) async {
    if (throwOnPull) throw StateError('offline');
    return page;
  }

  @override
  Future<SyncPushReceipt> push({required String deviceId, required List<EncryptedSyncEnvelope> envelopes, required OpaqueSyncCursor cursor}) async {
    if (throwOnPush) throw StateError('offline');
    pushed.addAll(envelopes);
    return SyncPushReceipt(acceptedEnvelopeIds: acknowledgedIds ?? envelopes.map((e) => e.envelopeId).toList(), cursor: OpaqueSyncCursor('push-next'));
  }
}

/// Test-only reversible mapping. It is intentionally not production crypto.
final class _FakeCrypto implements SyncCryptographyPort {
  int sealCalls = 0;
  int openCalls = 0;
  Uint8List? lastPlaintext;
  Uint8List? lastMetadata;
  Uint8List? forcedOpen;
  Uint8List? sealInputReference;
  Uint8List? openOutputReference;
  final Map<String, Uint8List> payloads = {};

  @override
  Future<SealedSyncPayload> seal({required Uint8List trustedPlaintext, required String recipientEpoch, required Uint8List authenticatedMetadata}) async {
    sealCalls++;
    sealInputReference = trustedPlaintext;
    lastPlaintext = Uint8List.fromList(trustedPlaintext);
    lastMetadata = Uint8List.fromList(authenticatedMetadata);
    return SealedSyncPayload(recipientEpoch: recipientEpoch, ciphertext: Uint8List.fromList([9]), signature: Uint8List.fromList([8]));
  }

  @override
  Future<Uint8List> open({required SealedSyncPayload payload, required Uint8List authenticatedMetadata}) async {
    openCalls++;
    if (forcedOpen case final value?) {
      openOutputReference = Uint8List.fromList(value);
      return openOutputReference!;
    }
    final id = utf8.decode(payload.ciphertext);
    openOutputReference = Uint8List.fromList(payloads[id]!);
    return openOutputReference!;
  }
}

final class _RecordingStore implements EventStore {
  final List<List<EventEnvelope>> transactions = [];
  bool fail = false;

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    if (fail) throw StateError('atomic rejection');
    transactions.add(List.unmodifiable(events));
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;

  @override
  Future<List<EventEnvelope>> readBySubject(ObjectRef subject, {int? limit}) async => const [];
}
