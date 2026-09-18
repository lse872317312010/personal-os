import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  test('restore verifies then appends the complete history once', () async {
    final store = _Store();
    final service = EventArchiveRestoreService(eventStore: store);
    final source = <EventEnvelope>[_event('event-1'), _event('event-2')];

    final result = await service.restore(EventArchiveCodec.encode(source));

    expect(result.eventCount, 2);
    expect(result.checksum, hasLength(64));
    expect(store.batches, hasLength(1));
    expect(
      store.batches.single
          .map(EventEnvelopeJsonCodec.encodeString)
          .toList(growable: false),
      source
          .map(EventEnvelopeJsonCodec.encodeString)
          .toList(growable: false),
    );
  });

  test('restore never writes a corrupted archive', () async {
    final store = _Store();
    final service = EventArchiveRestoreService(eventStore: store);
    final archive = EventArchiveCodec.encode(<EventEnvelope>[_event('event-1')])
        .replaceFirst('archive test', 'archive fake');

    await expectLater(
      service.restore(archive),
      throwsA(isA<EventArchiveException>()),
    );
    expect(store.batches, isEmpty);
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
        sessionOrRunId: id,
        onBehalfOf: 'primary-user',
      ),
      subjectRefs: <ObjectRef>[
        ObjectRef(type: 'agent_session', id: EntityId(id)),
        ObjectRef(type: 'profile', id: EntityId('primary-user')),
      ],
      correlationId: id,
      sensitivity: Sensitivity.d2,
      payload: const <String, Object?>{
        'expected_revision': 0,
        'agent_id': 'harness',
        'protocol_version': 'personal-os.mcp.v0',
        'purpose': 'archive test',
        'capabilities': <Object?>[],
      },
    );

final class _Store implements EventStore {
  final List<List<EventEnvelope>> batches = <List<EventEnvelope>>[];

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    batches.add(List<EventEnvelope>.unmodifiable(events));
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async =>
      const <EventEnvelope>[];
}
