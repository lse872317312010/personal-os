import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  final event = EventEnvelope(
    eventId: 'event-1',
    eventType: 'appearance.reviewed',
    eventVersion: 1,
    occurredAt: DateTime.utc(2026, 8, 24),
    recordedAt: DateTime.utc(2026, 8, 24),
    actor: _userActor,
    correlationId: 'correlation-1',
    sensitivity: Sensitivity.d2,
    payload: const <String, Object?>{
      'rating': 4,
      'notes': 'local review',
    },
  );

  test('request freezes immutable events and applies explicit policy', () {
    final request = EventExportRequest(
      events: [event],
      policy: EventExportPolicy(maxSensitivity: Sensitivity.d2),
    );

    expect(request.events, hasLength(1));
    expect(() => request.events.add(event), throwsUnsupportedError);
    expect(
      () => EventExportRequest(
        events: [event],
        policy: EventExportPolicy(maxSensitivity: Sensitivity.d1),
      ),
      throwsA(
        isA<EventExportDenied>().having(
          (error) => error.code,
          'code',
          'EVENT_EXPORT_SENSITIVITY_NOT_ALLOWED',
        ),
      ),
    );
  });

  test('D4 cannot be used as an export policy or event', () {
    expect(
      () => EventExportPolicy(maxSensitivity: Sensitivity.d4),
      throwsArgumentError,
    );

    final d4 = EventEnvelope(
      eventId: 'event-d4',
      eventType: 'private.raw',
      eventVersion: 1,
      occurredAt: DateTime.utc(2026, 8, 24),
      recordedAt: DateTime.utc(2026, 8, 24),
      actor: _userActor,
      correlationId: 'correlation-d4',
      sensitivity: Sensitivity.d4,
      payload: const <String, Object?>{},
    );

    expect(
      () => EventExportRequest(
        events: [d4],
        policy: EventExportPolicy(maxSensitivity: Sensitivity.d3),
      ),
      throwsA(isA<EventExportDenied>()),
    );
  });

  test('forbidden secret, path, and content hash fields are rejected', () {
    for (final field in ['key_alias', 'secret', 'file_path', 'content_hash']) {
      final forbidden = EventEnvelope(
        eventId: 'event-$field',
        eventType: 'unsafe.test',
        eventVersion: 1,
        occurredAt: DateTime.utc(2026, 8, 24),
        recordedAt: DateTime.utc(2026, 8, 24),
        actor: _userActor,
        correlationId: 'correlation-$field',
        sensitivity: Sensitivity.d1,
        payload: <String, Object?>{field: 'redacted'},
      );

      expect(
        () => EventExportRequest(
          events: [forbidden],
          policy: EventExportPolicy(maxSensitivity: Sensitivity.d1),
        ),
        throwsA(
          isA<EventExportDenied>().having(
            (error) => error.code,
            'code',
            'EVENT_EXPORT_FORBIDDEN_FIELD',
          ),
        ),
      );
    }
  });

  test('opaque result exposes only copied bytes and safe metadata', () {
    final source = <int>[1, 2, 3];
    final result = OpaqueEventExport(
      bytes: source,
      metadata: EventExportEnvelopeMetadata(
        format: 'personal-os.event-export',
        schemaVersion: 1,
        eventCount: 1,
        maxSensitivity: Sensitivity.d2,
        createdAt: DateTime.utc(2026, 8, 24),
      ),
    );
    source[0] = 9;
    final firstRead = result.bytes;
    firstRead[1] = 9;

    expect(result.bytes, orderedEquals([1, 2, 3]));
    expect(result.toString(), 'OpaqueEventExport(<redacted>)');
    expect(result.metadata.eventCount, 1);
    expect(result.metadata.maxSensitivity, Sensitivity.d2);
  });

  test('metadata rejects blank format, empty count, and D4', () {
    expect(
      () => EventExportEnvelopeMetadata(
        format: ' ',
        schemaVersion: 1,
        eventCount: 1,
        maxSensitivity: Sensitivity.d1,
        createdAt: DateTime.now(),
      ),
      throwsArgumentError,
    );
    expect(
      () => EventExportEnvelopeMetadata(
        format: '../plaintext',
        schemaVersion: 1,
        eventCount: 1,
        maxSensitivity: Sensitivity.d1,
        createdAt: DateTime.now(),
      ),
      throwsArgumentError,
    );
    expect(
      () => EventExportEnvelopeMetadata(
        format: 'opaque',
        schemaVersion: 1,
        eventCount: 0,
        maxSensitivity: Sensitivity.d1,
        createdAt: DateTime.now(),
      ),
      throwsArgumentError,
    );
  });
}

final _userActor = ActorRef(
  actorId: 'user-1',
  actorType: ActorType.user,
  authoritySource: 'local',
);
