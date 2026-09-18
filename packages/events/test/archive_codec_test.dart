import 'dart:convert';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:test/test.dart';

void main() {
  test('archive round trip is byte-stable and lossless', () {
    final events = <EventEnvelope>[_event('event-1'), _event('event-2')];

    final encoded = EventArchiveCodec.encode(events);
    final decoded = EventArchiveCodec.decode(encoded);
    final reencoded = EventArchiveCodec.encode(decoded.events);

    expect(reencoded, encoded);
    expect(decoded.events, hasLength(2));
    for (var index = 0; index < events.length; index += 1) {
      expect(
        EventEnvelopeJsonCodec.encodeString(decoded.events[index]),
        EventEnvelopeJsonCodec.encodeString(events[index]),
      );
    }
  });

  test('archive rejects changed event content', () {
    final encoded =
        EventArchiveCodec.encode(<EventEnvelope>[_event('event-1')]);
    final archive = jsonDecode(encoded) as Map<String, Object?>;
    final events = archive['events']! as List<Object?>;
    final event = events.single as Map<String, Object?>;
    final payload = event['payload']! as Map<String, Object?>;
    payload['purpose'] = 'tampered';

    expect(
      () => EventArchiveCodec.decode(jsonEncode(archive)),
      throwsA(
        isA<EventArchiveException>().having(
          (error) => error.code,
          'code',
          EventArchiveError.checksumMismatch,
        ),
      ),
    );
  });

  test('archive rejects duplicate event IDs before export', () {
    final event = _event('event-1');
    expect(
      () => EventArchiveCodec.encode(<EventEnvelope>[event, event]),
      throwsA(
        isA<EventArchiveException>().having(
          (error) => error.code,
          'code',
          EventArchiveError.duplicateEventId,
        ),
      ),
    );
  });
}

EventEnvelope _event(String id) => EventEnvelope(
      eventId: id,
      eventType: EventTypes.agentSessionOpened,
      eventVersion: 1,
      occurredAt: DateTime.utc(2026, 9, 18, 12),
      recordedAt: DateTime.utc(2026, 9, 18, 12),
      actor: ActorRef(
        actorId: 'harness',
        actorType: ActorType.agent,
        authoritySource: 'offline_bundle',
        sessionOrRunId: 'session-1',
        onBehalfOf: 'primary-user',
      ),
      subjectRefs: <ObjectRef>[
        ObjectRef(type: 'agent_session', id: EntityId('session-1')),
        ObjectRef(type: 'profile', id: EntityId('primary-user')),
      ],
      correlationId: 'session-1',
      sensitivity: Sensitivity.d2,
      payload: const <String, Object?>{
        'expected_revision': 0,
        'agent_id': 'harness',
        'protocol_version': 'personal-os.mcp.v0',
        'purpose': 'archive test',
        'capabilities': <Object?>[],
      },
    );
