import 'dart:convert';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_sqlite_vault_schema/sqlite_vault.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

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

final class FakeSqlExecutor implements SqlExecutor {
  Map<String, SqlRow> events = <String, SqlRow>{};
  List<SqlRow> subjects = <SqlRow>[];
  Map<String, SqlRow> projections = <String, SqlRow>{};
  Map<String, SqlRow> outbox = <String, SqlRow>{};
  final List<String> projectionQueryKeys = <String>[];
  bool failOnOutbox = false;
  int transactionCount = 0;
  int commitCount = 0;
  int rollbackCount = 0;

  @override
  Future<int> execute(String sql, [List<Object?> parameters = const []]) =>
      throw UnsupportedError('writes require a transaction');

  @override
  Future<List<SqlRow>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async => _query(events, subjects, projections, sql, parameters);

  @override
  Future<T> transaction<T>(Future<T> Function(SqlTransaction tx) action) async {
    transactionCount += 1;
    final stagedEvents = _copyMap(events);
    final stagedSubjects = subjects.map(Map<String, Object?>.of).toList();
    final stagedProjections = _copyMap(projections);
    final stagedOutbox = _copyMap(outbox);
    final tx = _FakeTransaction(
      stagedEvents,
      stagedSubjects,
      stagedProjections,
      stagedOutbox,
      projectionQueryKeys,
      failOnOutbox: failOnOutbox,
    );
    try {
      final result = await action(tx);
      events = stagedEvents;
      subjects = stagedSubjects;
      projections = stagedProjections;
      outbox = stagedOutbox;
      commitCount += 1;
      return result;
    } catch (_) {
      rollbackCount += 1;
      rethrow;
    }
  }
}

final class _FakeTransaction implements SqlTransaction {
  _FakeTransaction(
    this.events,
    this.subjects,
    this.projections,
    this.outbox,
    this.projectionQueryKeys, {
    required this.failOnOutbox,
  });

  final Map<String, SqlRow> events;
  final List<SqlRow> subjects;
  final Map<String, SqlRow> projections;
  final Map<String, SqlRow> outbox;
  final List<String> projectionQueryKeys;
  final bool failOnOutbox;

  @override
  Future<List<SqlRow>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async => _query(
        events,
        subjects,
        projections,
        sql,
        parameters,
        projectionQueryKeys: projectionQueryKeys,
      );

  @override
  Future<int> execute(String sql, [List<Object?> parameters = const []]) async {
    if (sql.startsWith('INSERT INTO event_log')) {
      events[parameters[0]! as String] = _eventRow(parameters);
      return 1;
    }
    if (sql.startsWith('INSERT INTO event_subjects')) {
      subjects.add(<String, Object?>{
        'event_id': parameters[0],
        'subject_type': parameters[1],
        'subject_id': parameters[2],
        'subject_revision': parameters[3],
        'subject_ordinal': parameters[4],
      });
      return 1;
    }
    if (sql.startsWith('INSERT INTO projections')) {
      final key = '${parameters[1]}:${parameters[2]}';
      if (projections.containsKey(key)) return 0;
      projections[key] = _projectionRow(parameters);
      return 1;
    }
    if (sql.startsWith('UPDATE projections')) {
      final key = '${parameters[6]}:${parameters[7]}';
      final current = projections[key];
      if (current == null || current['revision'] != parameters[8]) return 0;
      projections[key] = <String, Object?>{
        'revision': parameters[0],
        'last_event_id': parameters[1],
        'state_json': parameters[2],
        'state': jsonDecode(parameters[2]! as String)['state'],
      };
      return 1;
    }
    if (sql.startsWith('INSERT INTO outbox')) {
      if (failOnOutbox) throw StateError('injected outbox failure');
      outbox[parameters[0]! as String] = <String, Object?>{
        'event_id': parameters[1],
      };
      return 1;
    }
    throw UnsupportedError(sql);
  }
}

Future<List<SqlRow>> _query(
  Map<String, SqlRow> events,
  List<SqlRow> subjects,
  Map<String, SqlRow> projections,
  String sql,
  List<Object?> parameters, {
  List<String>? projectionQueryKeys,
}) async {
  if (sql.contains('FROM projections')) {
    final key = '${parameters[1]}:${parameters[2]}';
    projectionQueryKeys?.add(key);
    final row = projections[key];
    return row == null ? <SqlRow>[] : <SqlRow>[row];
  }
  if (sql.contains('FROM event_log e')) {
    Iterable<SqlRow> selected = events.values;
    if (sql.contains('WHERE e.event_id = ?')) {
      final row = events[parameters.single];
      selected = row == null ? const <SqlRow>[] : <SqlRow>[row];
    } else if (sql.contains('WHERE s.subject_type = ?')) {
      final ids = subjects
          .where((row) =>
              row['subject_type'] == parameters[0] &&
              row['subject_id'] == parameters[1])
          .map((row) => row['event_id'])
          .toSet();
      selected = selected.where((row) => ids.contains(row['event_id']));
    }
    return selected.map((row) {
      final refs = subjects
          .where((subject) => subject['event_id'] == row['event_id'])
          .toList()
        ..sort((a, b) => (a['subject_ordinal']! as int)
            .compareTo(b['subject_ordinal']! as int));
      final encodedRefs = refs
          .map((subject) => <String, Object?>{
                'type': subject['subject_type'],
                'id': subject['subject_id'],
                if (subject['subject_revision'] != null)
                  'revision': subject['subject_revision'],
                'ordinal': subject['subject_ordinal'],
              })
          .toList();
      return <String, Object?>{
        ...row,
        'subject_refs_json': jsonEncode(encodedRefs),
      };
    }).toList();
  }
  throw UnsupportedError(sql);
}

SqlRow _eventRow(List<Object?> p) => <String, Object?>{
      'event_id': p[0],
      'event_type': p[1],
      'event_version': p[2],
      'occurred_at': p[3],
      'recorded_at': p[4],
      'actor_json': p[5],
      'correlation_id': p[6],
      'causation_id': p[7],
      'source_refs_json': p[8],
      'consent_refs_json': p[9],
      'sensitivity': p[10],
      'payload_json': p[11],
      'integrity_json': p[12],
      'extensions_json': p[13],
    };

SqlRow _projectionRow(List<Object?> p) => <String, Object?>{
      'revision': p[3],
      'last_event_id': p[4],
      'state_json': p[5],
      'state': jsonDecode(p[5]! as String)['state'],
    };

Map<String, SqlRow> _copyMap(Map<String, SqlRow> source) =>
    source.map((key, value) => MapEntry(key, Map<String, Object?>.of(value)));
