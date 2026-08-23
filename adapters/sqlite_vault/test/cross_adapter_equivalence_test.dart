/// Cross-adapter equivalence contract for `EventStore.appendAll`.
///
/// Drives the SAME canonical event batches through both
/// [InMemoryEventStore] (pure-Dart candidate) and [SqliteVaultEventStore]
/// (backed by the pure-Dart [FakeSqlExecutor], standing in for a native
/// SQLCipher driver). Asserts the two adapters agree on:
///
/// 1. **Outcome parity** — `appendAll` either completes on both or throws
///    on both (atomicity is never asymmetric).
/// 2. **Conflict-type parity** — revision conflicts surface as
///    [EventAppendConflict] on both (ADR-0013 transaction guarantees).
/// 3. **D4 parity** — D4 events are rejected on both before any partial
///    write; the exception TYPE intentionally differs (in-memory raises
///    `StateError`, sqlite raises `VaultSchemaViolation`) but the
///    no-partial-state guarantee is identical.
/// 4. **Read-back parity** — after a successful append, `readById` and
///    `readBySubject` return canonically-equal events in the same order.
/// 5. **Idempotency parity** — re-appending an identical event is a
///    no-op on both.
///
/// This is the ADR-0013 "cross-adapter equivalence" guard: it runs in CI
/// (no native SQLCipher needed) because `SqliteVaultEventStore` is
/// driver-neutral and `FakeSqlExecutor` honours the SQL contract.

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_in_memory/in_memory.dart';
import 'package:personal_os_sqlite_vault_schema/sqlite_vault.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

import 'helpers/fake_sql_executor.dart';

void main() {
  group('cross-adapter appendAll equivalence', () {
    test('single event commits on both and read-back matches', () async {
      final event = _goal('e1', objectId: 'goal-1');
      final inMemory = InMemoryEventStore();
      final sqlite = SqliteVaultEventStore(FakeSqlExecutor());

      await inMemory.appendAll(<EventEnvelope>[event]);
      await sqlite.appendAll(<EventEnvelope>[event]);

      await _expectReadByIdParity(inMemory, sqlite, 'e1');
      await _expectReadBySubjectParity(
        inMemory,
        sqlite,
        ObjectRef(type: 'goal', id: EntityId('goal-1')),
        expectedIds: <String>['e1'],
      );
    });

    test('multi-subject batch commits on both with identical read-back',
        () async {
      final e1 = _goal('e1', objectId: 'goal-1', at: _t(0));
      final e2 = _goal('e2', objectId: 'goal-2', at: _t(1));
      final inMemory = InMemoryEventStore();
      final sqlite = SqliteVaultEventStore(FakeSqlExecutor());

      await inMemory.appendAll(<EventEnvelope>[e1, e2]);
      await sqlite.appendAll(<EventEnvelope>[e1, e2]);

      await _expectReadBySubjectParity(
        inMemory,
        sqlite,
        ObjectRef(type: 'goal', id: EntityId('goal-1')),
        expectedIds: <String>['e1'],
      );
      await _expectReadBySubjectParity(
        inMemory,
        sqlite,
        ObjectRef(type: 'goal', id: EntityId('goal-2')),
        expectedIds: <String>['e2'],
      );
    });

    test('readBySubject returns multiple events in the same order on both',
        () async {
      // goalCreated then deletionRequested share the goal-1 subject ref,
      // so readBySubject(goal-1) must return [e1, e2] on both adapters.
      final e1 = _goal('e1', objectId: 'goal-1', at: _t(0));
      final e2 = _deletion('e2', at: _t(1));
      final inMemory = InMemoryEventStore();
      final sqlite = SqliteVaultEventStore(FakeSqlExecutor());

      await inMemory.appendAll(<EventEnvelope>[e1, e2]);
      await sqlite.appendAll(<EventEnvelope>[e1, e2]);

      await _expectReadBySubjectParity(
        inMemory,
        sqlite,
        ObjectRef(type: 'goal', id: EntityId('goal-1')),
        expectedIds: <String>['e1', 'e2'],
      );
    });

    test('duplicate event_id is an idempotent no-op on both', () async {
      final event = _goal('e1', objectId: 'goal-1');
      final inMemory = InMemoryEventStore();
      final sqlite = SqliteVaultEventStore(FakeSqlExecutor());

      await inMemory.appendAll(<EventEnvelope>[event]);
      await sqlite.appendAll(<EventEnvelope>[event]);
      // Re-append the identical event.
      await inMemory.appendAll(<EventEnvelope>[event]);
      await sqlite.appendAll(<EventEnvelope>[event]);

      await _expectReadByIdParity(inMemory, sqlite, 'e1');
      final inMemorySubject = await inMemory.readBySubject(
        ObjectRef(type: 'goal', id: EntityId('goal-1')),
      );
      final sqliteSubject = await sqlite.readBySubject(
        ObjectRef(type: 'goal', id: EntityId('goal-1')),
      );
      expect(inMemorySubject, hasLength(1));
      expect(sqliteSubject, hasLength(1));
      expect(
        EventEnvelopeJsonCodec.encodeString(inMemorySubject.single),
        EventEnvelopeJsonCodec.encodeString(sqliteSubject.single),
      );
    });

    test('readById for a missing id returns null on both', () async {
      final inMemory = InMemoryEventStore();
      final sqlite = SqliteVaultEventStore(FakeSqlExecutor());

      expect(await inMemory.readById('never-appended'), isNull);
      expect(await sqlite.readById('never-appended'), isNull);
    });

    test(
        'revision conflict throws EventAppendConflict on both with no partial '
        'state', () async {
      // expected_revision 7 on a fresh goal => reducer rejects as a
      // revision conflict (ADR-0013 transaction guarantee).
      final conflict = _goal(
        'e-conflict',
        objectId: 'goal-x',
        expectedRevision: 7,
      );
      final inMemory = InMemoryEventStore();
      final sqlite = SqliteVaultEventStore(FakeSqlExecutor());

      await expectLater(
        inMemory.appendAll(<EventEnvelope>[conflict]),
        throwsA(isA<EventAppendConflict>()),
      );
      await expectLater(
        sqlite.appendAll(<EventEnvelope>[conflict]),
        throwsA(isA<EventAppendConflict>()),
      );

      // No partial state on either adapter.
      expect(await inMemory.readById('e-conflict'), isNull);
      expect(await sqlite.readById('e-conflict'), isNull);
    });

    test('mid-batch failure rolls back every prior event on both', () async {
      final e1 = _goal('e1', objectId: 'goal-1', at: _t(0));
      final e2 = _goal(
        'e2',
        objectId: 'goal-2',
        expectedRevision: 7,
        at: _t(1),
      );
      final inMemory = InMemoryEventStore();
      final sqlite = SqliteVaultEventStore(FakeSqlExecutor());

      await expectLater(
        inMemory.appendAll(<EventEnvelope>[e1, e2]),
        throwsA(isA<EventAppendConflict>()),
      );
      await expectLater(
        sqlite.appendAll(<EventEnvelope>[e1, e2]),
        throwsA(isA<EventAppendConflict>()),
      );

      // Atomicity: e1 must NOT be readable after the batch failed.
      expect(await inMemory.readById('e1'), isNull);
      expect(await sqlite.readById('e1'), isNull);
      expect(
        await inMemory.readBySubject(
          ObjectRef(type: 'goal', id: EntityId('goal-1')),
        ),
        isEmpty,
      );
      expect(
        await sqlite.readBySubject(
          ObjectRef(type: 'goal', id: EntityId('goal-1')),
        ),
        isEmpty,
      );
    });

    test('D4 event is rejected on both before any partial write', () async {
      // Outcome parity: both throw. Exception TYPE intentionally differs
      // (in-memory => StateError, sqlite => VaultSchemaViolation); the
      // contract that matters is "no D4 enters storage and no partial
      // state survives".
      final d4 = _goal(
        'd4',
        objectId: 'goal-d4',
        sensitivity: Sensitivity.d4,
      );
      final inMemory = InMemoryEventStore();
      final sqlite = SqliteVaultEventStore(FakeSqlExecutor());

      final inMemoryOutcome = await _capture(inMemory, <EventEnvelope>[d4]);
      final sqliteOutcome = await _capture(sqlite, <EventEnvelope>[d4]);

      expect(
        inMemoryOutcome.succeeded,
        isFalse,
        reason: 'in-memory must reject D4',
      );
      expect(
        sqliteOutcome.succeeded,
        isFalse,
        reason: 'sqlite must reject D4',
      );
      expect(inMemoryOutcome.error, isA<StateError>());
      expect(sqliteOutcome.error, isA<VaultSchemaViolation>());

      expect(await inMemory.readById('d4'), isNull);
      expect(await sqlite.readById('d4'), isNull);
    });

    test('D4 in a mixed batch rejects the whole batch atomically on both',
        () async {
      final safe = _goal('safe', objectId: 'goal-safe', at: _t(0));
      final d4 = _goal(
        'd4',
        objectId: 'goal-d4',
        sensitivity: Sensitivity.d4,
        at: _t(1),
      );
      final inMemory = InMemoryEventStore();
      final sqlite = SqliteVaultEventStore(FakeSqlExecutor());

      final inMemoryOutcome = await _capture(
        inMemory,
        <EventEnvelope>[safe, d4],
      );
      final sqliteOutcome = await _capture(
        sqlite,
        <EventEnvelope>[safe, d4],
      );

      expect(inMemoryOutcome.succeeded, isFalse);
      expect(sqliteOutcome.succeeded, isFalse);

      // The safe event must NOT survive the rejected batch on either adapter.
      expect(await inMemory.readById('safe'), isNull);
      expect(await sqlite.readById('safe'), isNull);
    });
  });
}

/// Captures whether `appendAll` succeeded or threw, without failing the test.
Future<_AppendOutcome> _capture(
  EventStore store,
  List<EventEnvelope> events,
) async {
  try {
    await store.appendAll(events);
    return const _AppendOutcome(succeeded: true, error: null);
  } on Object catch (error) {
    return _AppendOutcome(succeeded: false, error: error);
  }
}

class _AppendOutcome {
  const _AppendOutcome({required this.succeeded, required this.error});

  final bool succeeded;
  final Object? error;
}

Future<void> _expectReadByIdParity(
  EventStore inMemory,
  EventStore sqlite,
  String eventId,
) async {
  final inMemoryEvent = await inMemory.readById(eventId);
  final sqliteEvent = await sqlite.readById(eventId);
  if (inMemoryEvent == null && sqliteEvent == null) return;
  expect(inMemoryEvent, isNotNull, reason: 'in-memory missing $eventId');
  expect(sqliteEvent, isNotNull, reason: 'sqlite missing $eventId');
  expect(
    EventEnvelopeJsonCodec.encodeString(inMemoryEvent!),
    EventEnvelopeJsonCodec.encodeString(sqliteEvent!),
    reason: 'readById content diverged for $eventId',
  );
}

Future<void> _expectReadBySubjectParity(
  EventStore inMemory,
  EventStore sqlite,
  ObjectRef subject, {
  required List<String> expectedIds,
}) async {
  final inMemoryEvents = await inMemory.readBySubject(subject);
  final sqliteEvents = await sqlite.readBySubject(subject);

  final inMemoryIds = inMemoryEvents.map((e) => e.eventId).toList();
  final sqliteIds = sqliteEvents.map((e) => e.eventId).toList();
  expect(inMemoryIds, expectedIds, reason: 'in-memory readBySubject order');
  expect(sqliteIds, expectedIds, reason: 'sqlite readBySubject order');

  // Canonical content parity for each returned event.
  expect(inMemoryEvents.length, sqliteEvents.length);
  for (var i = 0; i < inMemoryEvents.length; i++) {
    expect(
      EventEnvelopeJsonCodec.encodeString(inMemoryEvents[i]),
      EventEnvelopeJsonCodec.encodeString(sqliteEvents[i]),
      reason: 'readBySubject content diverged at index $i',
    );
  }
}

DateTime _t(int minute) => DateTime.utc(2026, 8, 20, 0, minute);

EventEnvelope _goal(
  String eventId, {
  required String objectId,
  int expectedRevision = 0,
  Sensitivity sensitivity = Sensitivity.d1,
  DateTime? at,
}) {
  final instant = at ?? _t(0);
  return EventEnvelope(
    eventId: eventId,
    eventType: EventTypes.goalCreated,
    eventVersion: 1,
    occurredAt: instant,
    recordedAt: instant,
    actor: ActorRef(
      actorId: 'user-1',
      actorType: ActorType.user,
      authoritySource: 'local_user_session',
    ),
    subjectRefs: <ObjectRef>[
      ObjectRef(type: 'goal', id: EntityId(objectId)),
    ],
    correlationId: 'correlation-1',
    sensitivity: sensitivity,
    payload: <String, Object?>{'expected_revision': expectedRevision},
  );
}

EventEnvelope _deletion(String eventId, {DateTime? at}) {
  final instant = at ?? _t(1);
  return EventEnvelope(
    eventId: eventId,
    eventType: EventTypes.deletionRequested,
    eventVersion: 1,
    occurredAt: instant,
    recordedAt: instant,
    actor: ActorRef(
      actorId: 'user-1',
      actorType: ActorType.user,
      authoritySource: 'local_user_session',
    ),
    subjectRefs: <ObjectRef>[
      ObjectRef(type: 'deletion', id: EntityId('deletion-1')),
      ObjectRef(type: 'goal', id: EntityId('goal-1')),
    ],
    correlationId: 'correlation-delete',
    sensitivity: Sensitivity.d2,
    payload: const <String, Object?>{'expected_revision': 0},
  );
}
