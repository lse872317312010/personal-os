import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_sqlite_vault_schema/sqlite_vault.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

import 'helpers/fake_sql_executor.dart';

void main() {
  group('SqliteVaultEventStore transaction contract', () {
    test('commits event, projection and outbox together', () async {
      final db = FakeSqlExecutor();
      final store = SqliteVaultEventStore(db);

      await store.appendAll(<EventEnvelope>[_goal('e1')]);

      expect(db.events, hasLength(1));
      expect(db.projections['goal:goal-1']?['revision'], 1);
      expect(db.outbox, hasLength(1));
      expect(db.commitCount, 1);
    });

    test('rolls every stage back when a write fails', () async {
      final db = FakeSqlExecutor()..failOnOutbox = true;
      final store = SqliteVaultEventStore(db);

      await expectLater(
        store.appendAll(<EventEnvelope>[_goal('e1')]),
        throwsA(isA<StateError>()),
      );

      expect(db.events, isEmpty);
      expect(db.subjects, isEmpty);
      expect(db.projections, isEmpty);
      expect(db.outbox, isEmpty);
      expect(db.rollbackCount, 1);
    });

    test('identical IDs in a batch and database are idempotent', () async {
      final db = FakeSqlExecutor();
      final store = SqliteVaultEventStore(db);
      final event = _goal('e1');

      await store.appendAll(<EventEnvelope>[event, event]);
      await store.appendAll(<EventEnvelope>[event]);

      expect(db.events, hasLength(1));
      expect(db.outbox, hasLength(1));
      expect(db.projections['goal:goal-1']?['revision'], 1);
    });

    test('same ID with different canonical content is rejected', () async {
      final db = FakeSqlExecutor();
      final store = SqliteVaultEventStore(db);
      await store.appendAll(<EventEnvelope>[_goal('e1')]);

      await expectLater(
        store.appendAll(<EventEnvelope>[_goal('e1', objectId: 'goal-2')]),
        throwsA(isA<EventAppendConflict>()),
      );
      await expectLater(
        store.appendAll(<EventEnvelope>[
          _goal('e2'),
          _goal('e2', objectId: 'goal-2'),
        ]),
        throwsA(isA<EventAppendConflict>()),
      );
      expect(db.events, hasLength(1));
    });

    test('read paths reconstruct pinned subject revisions', () async {
      final db = FakeSqlExecutor();
      final store = SqliteVaultEventStore(db);
      final event = _goal('e1', pinnedRevision: 9);
      await store.appendAll(<EventEnvelope>[event]);

      final byId = await store.readById('e1');
      final bySubject = await store.readBySubject(event.subjectRefs.single);

      expect(byId!.subjectRefs.single.revision!.value, 9);
      expect(bySubject.single.subjectRefs.single.revision!.value, 9);
    });

    test('loads every existing deletion projection before reducing', () async {
      final db = FakeSqlExecutor();
      final store = SqliteVaultEventStore(db);
      await store.appendAll(<EventEnvelope>[
        _goal('g1'),
        _deletionRequested('d1'),
      ]);

      expect(db.projectionQueryKeys, contains('goal:goal-1'));
      expect(db.projections['goal:goal-1']?['revision'], 2);
      expect(
        db.projections['goal:goal-1']?['state'],
        'unavailable_pending_deletion',
      );
    });

    test('D4 is rejected before opening a transaction', () async {
      final db = FakeSqlExecutor();
      final store = SqliteVaultEventStore(db);

      await expectLater(
        store.appendAll(<EventEnvelope>[
          _goal('d4', sensitivity: Sensitivity.d4),
        ]),
        throwsA(isA<VaultSchemaViolation>()),
      );
      expect(db.transactionCount, 0);
      expect(db.events, isEmpty);
    });
  });
}

EventEnvelope _goal(
  String eventId, {
  String objectId = 'goal-1',
  int? pinnedRevision,
  Sensitivity sensitivity = Sensitivity.d1,
}) {
  final instant = DateTime.utc(2026, 8, 20);
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
      ObjectRef(
        type: 'goal',
        id: EntityId(objectId),
        revision: pinnedRevision == null ? null : Revision(pinnedRevision),
      ),
    ],
    correlationId: 'correlation-1',
    sensitivity: sensitivity,
    payload: const <String, Object?>{'expected_revision': 0},
  );
}

EventEnvelope _deletionRequested(String eventId) {
  final instant = DateTime.utc(2026, 8, 20, 0, 1);
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
