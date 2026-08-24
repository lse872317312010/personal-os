import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_in_memory/in_memory.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryEventStore', () {
    test('appends event, projection, and outbox atomically', () {
      final store = InMemoryEventStore();
      final result = store.append(_event('e1', 0));

      expect(result.committed, isTrue);
      expect(store.readEvents().map((e) => e.event.eventId), ['e1']);
      expect(store.readProjection('goal', 'goal-1')?.revision.value, 1);
      expect(store.readOutbox().map((e) => e.eventId), ['e1']);
    });

    test('duplicate event_id is an idempotent no-op', () {
      final store = InMemoryEventStore();
      store.append(_event('e1', 0));

      final result = store.append(_event('e1', 999));

      expect(result.committed, isTrue);
      expect(result.duplicateEventIds, ['e1']);
      expect(store.readEvents(), hasLength(1));
      expect(store.readOutbox(), hasLength(1));
      expect(store.readProjection('goal', 'goal-1')?.revision.value, 1);
    });

    test('same event_id with different content is a stable conflict', () async {
      final store = InMemoryEventStore();
      await store.appendAll([_event('e1', 0, objectId: 'goal-1')]);

      await expectLater(
        store.appendAll([_event('e1', 0, objectId: 'goal-2')]),
        throwsA(
          isA<EventAppendConflict>()
              .having((error) => error.code, 'code',
                  PersistenceErrorCode.eventConflict)
              .having((error) => error.toString(), 'toString',
                  isNot(contains('goal-2'))),
        ),
      );
      expect(store.readEvents().map((stored) => stored.event.eventId), ['e1']);
      expect(store.readProjection('goal', 'goal-2'), isNull);
    });

    test('same event_id with different content in one batch rolls back', () {
      final store = InMemoryEventStore();
      final result = store.appendTransaction([
        _event('e1', 0, objectId: 'goal-1'),
        _event('e1', 0, objectId: 'goal-2'),
      ]);

      expect(result.committed, isFalse);
      expect(result.failure, AppendFailure.eventConflict);
      expect(result.reasonCode, PersistenceErrorCode.eventConflict);
      expect(store.readEvents(), isEmpty);
      expect(store.readOutbox(), isEmpty);
      expect(store.readAllProjections(), isEmpty);
    });

    test('revision conflict rejects the whole batch without partial commit',
        () {
      final store = InMemoryEventStore();
      final result = store.appendTransaction([
        _event('e1', 0, objectId: 'goal-1'),
        _event('e2', 7, objectId: 'goal-2'),
      ]);

      expect(result.committed, isFalse);
      expect(result.failure, AppendFailure.revisionConflict);
      expect(result.failedEventId, 'e2');
      expect(store.readEvents(), isEmpty);
      expect(store.readAllProjections(), isEmpty);
      expect(store.readOutbox(), isEmpty);
    });

    test('invalid transition also leaves no partial batch state', () {
      final store = InMemoryEventStore();
      final result = store.appendTransaction([
        _event('e1', 0),
        _event('e2', 1, eventType: EventTypes.goalCompleted),
      ]);

      expect(result.committed, isFalse);
      expect(result.failure, AppendFailure.invalidEvent);
      expect(store.readEvents(), isEmpty);
      expect(store.readOutbox(), isEmpty);
    });

    test('reads use stable sequences and outbox acknowledgement is idempotent',
        () {
      final store = InMemoryEventStore();
      store.append(_event('z-event', 0, objectId: 'goal-z'));
      store.append(_event('a-event', 0, objectId: 'goal-a'));

      expect(store.readEvents().map((e) => e.sequence), [1, 2]);
      expect(
          store.readEvents(afterSequence: 1).single.event.eventId, 'a-event');
      expect(store.acknowledgeOutbox(1), isTrue);
      expect(store.acknowledgeOutbox(1), isTrue);
      expect(store.readOutbox().map((e) => e.sequence), [2]);
      expect(
        store.readOutbox(includeAcknowledged: true).map((e) => e.sequence),
        [1, 2],
      );
    });

    test('duplicate inside a batch only commits the first occurrence', () {
      final store = InMemoryEventStore();
      final result =
          store.appendTransaction([_event('e1', 0), _event('e1', 0)]);

      expect(result.appendedEventIds, ['e1']);
      expect(result.duplicateEventIds, ['e1']);
      expect(store.readEvents(), hasLength(1));
      expect(store.readOutbox(), hasLength(1));
    });

    test('implements the asynchronous EventStore read contract', () async {
      final EventStore store = InMemoryEventStore();
      await store.appendAll([
        _event('e1', 0, objectId: 'goal-1'),
        _event('e2', 0, objectId: 'goal-2'),
      ]);

      expect((await store.readById('e2'))?.eventId, 'e2');
      expect(await store.readById('missing'), isNull);
      final events = await store.readBySubject(
        ObjectRef(type: 'goal', id: EntityId('goal-1')),
      );
      expect(events.map((event) => event.eventId), ['e1']);
    });

    test('formal append port exposes a stable revision conflict', () async {
      final EventStore store = InMemoryEventStore();

      await expectLater(
        store.appendAll([_event('e1', 4)]),
        throwsA(
          isA<EventAppendConflict>().having(
            (error) => error.message,
            'message',
            ReductionReason.revisionConflict,
          ),
        ),
      );
      expect(await store.readById('e1'), isNull);
    });

    test('formal append maps reducer rejection reasons to stable conflicts',
        () async {
      final EventStore store = InMemoryEventStore();

      await expectLater(
        store.appendAll([_event('unsupported', 0, eventVersion: 2)]),
        throwsA(
          isA<EventAppendConflict>().having(
            (error) => error.code,
            'code',
            PersistenceErrorCode.eventConflict,
          ),
        ),
      );
    });

    test('negative read limits fail closed with a stable read error', () async {
      final EventStore store = InMemoryEventStore();

      await expectLater(
        store.readBySubject(
          ObjectRef(type: 'goal', id: EntityId('goal-1')),
          limit: -1,
        ),
        throwsA(
          isA<PersistenceException>().having(
            (error) => error.code,
            'code',
            PersistenceErrorCode.readFailed,
          ),
        ),
      );
    });

    test('D4 event is rejected before any store mutation', () async {
      final store = InMemoryEventStore();

      await expectLater(
        store.appendAll([_event('d4', 0, sensitivity: Sensitivity.d4)]),
        throwsA(
          isA<PersistenceException>()
              .having((error) => error.code, 'code',
                  PersistenceErrorCode.d4PersistenceForbidden)
              .having((error) => error.message, 'message',
                  'event_append_rejected:d4_persistence_forbidden'),
        ),
      );
      expect(store.readEvents(), isEmpty);
      expect(store.readAllProjections(), isEmpty);
      expect(store.readOutbox(), isEmpty);
    });

    test('D4 in a mixed formal batch rejects all with zero side effects',
        () async {
      final store = InMemoryEventStore();
      await expectLater(
        store.appendAll([
          _event('d1', 0, objectId: 'safe-goal'),
          _event(
            'd4',
            0,
            objectId: 'forbidden-goal',
            sensitivity: Sensitivity.d4,
          ),
        ]),
        throwsA(
          isA<PersistenceException>().having(
            (error) => error.code,
            'code',
            PersistenceErrorCode.d4PersistenceForbidden,
          ),
        ),
      );
      expect(store.readEvents(), isEmpty);
      expect(store.readAllProjections(), isEmpty);
      expect(store.readOutbox(), isEmpty);
    });
  });
}

EventEnvelope _event(
  String eventId,
  int expectedRevision, {
  String objectId = 'goal-1',
  String eventType = EventTypes.goalCreated,
  int eventVersion = 1,
  Sensitivity sensitivity = Sensitivity.d1,
}) {
  final instant = DateTime.utc(2026, 8, 20);
  return EventEnvelope(
    eventId: eventId,
    eventType: eventType,
    eventVersion: eventVersion,
    occurredAt: instant,
    recordedAt: instant,
    actor: ActorRef(
      actorId: 'user-1',
      actorType: ActorType.user,
      authoritySource: 'local_user_session',
    ),
    subjectRefs: [ObjectRef(type: 'goal', id: EntityId(objectId))],
    correlationId: 'correlation-1',
    sensitivity: sensitivity,
    payload: {'expected_revision': expectedRevision},
  );
}
