import 'dart:convert';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'sqlite_vault_schema.dart';

typedef SqlRow = Map<String, Object?>;

abstract interface class SqlExecutor {
  Future<List<SqlRow>> query(String sql, [List<Object?> parameters = const []]);
  Future<int> execute(String sql, [List<Object?> parameters = const []]);
  Future<T> transaction<T>(Future<T> Function(SqlTransaction tx) action);
}

abstract interface class SqlTransaction {
  Future<List<SqlRow>> query(String sql, [List<Object?> parameters = const []]);
  Future<int> execute(String sql, [List<Object?> parameters = const []]);
}

/// Driver-neutral SQLite [EventStore]. It neither opens a database nor owns
/// SQLCipher keys; those responsibilities stay in a concrete platform driver.
final class SqliteVaultEventStore implements EventStore {
  SqliteVaultEventStore(this._database, {this.outboxDestination = 'relay'});

  final SqlExecutor _database;
  final String outboxDestination;

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    if (events.isEmpty) return;
    try {
      for (final event in events) {
        _validate(event);
      }
      final uniqueEvents = _deduplicateBatch(events);
      await _database.transaction((tx) async {
        final projections = <String, ObjectProjection>{};
        final seen = <String>{};
        for (final event in uniqueEvents) {
          final existing = await tx.query(
            _selectEventByIdSql,
            <Object?>[event.eventId],
          );
          if (existing.isNotEmpty) {
            final persisted = _decodeRow(existing.single);
            if (!_sameEventContentForIdempotency(persisted, event)) {
              throw EventAppendConflict(PersistenceErrorCode.eventConflict);
            }
            continue;
          }

          final relevantSubjects = _projectionSubjects(event);
          for (final ref in relevantSubjects) {
            final key = '${ref.type}:${ref.id.value}';
            if (projections.containsKey(key)) continue;
            final rows = await tx.query(
              'SELECT state_json FROM projections WHERE projection_type = ? '
              'AND subject_type = ? AND subject_id = ? LIMIT 1',
              <Object?>['core', ref.type, ref.id.value],
            );
            if (rows.isNotEmpty) {
              projections[key] = ObjectProjectionJsonCodec.decodeString(
                rows.single['state_json']! as String,
              );
            }
          }
          final priorRevisions = <String, int>{
            for (final ref in relevantSubjects)
              '${ref.type}:${ref.id.value}':
                  projections['${ref.type}:${ref.id.value}']?.revision.value ??
                      0,
          };
          final result = reduceCore(
            projections: projections,
            seenEventIds: seen,
            event: event,
          );
          if (result.disposition != ReductionDisposition.applied) {
            throw EventAppendConflict(
              result.reasonCode ?? PersistenceErrorCode.eventConflict,
            );
          }
          projections
            ..clear()
            ..addAll(result.projections);
          seen
            ..clear()
            ..addAll(result.seenEventIds);

          final encoded = EventEnvelopeJsonCodec.encode(event);
          await tx.execute(_insertEventSql, _eventParameters(encoded));
          for (final indexed in event.subjectRefs.indexed) {
            final (ordinal, ref) = indexed;
            await tx.execute(
              'INSERT INTO event_subjects '
              '(event_id, subject_type, subject_id, subject_revision, '
              'subject_ordinal) VALUES (?, ?, ?, ?, ?)',
              <Object?>[
                event.eventId,
                ref.type,
                ref.id.value,
                ref.revision?.value,
                ordinal,
              ],
            );
          }
          for (final projection in result.projections.values) {
            if (projection.lastEventId == event.eventId) {
              final projectionKey =
                  '${projection.objectType}:${projection.id.value}';
              await _writeProjection(
                tx,
                projection,
                priorRevisions[projectionKey] ?? 0,
                event.sensitivity.name.toUpperCase(),
                event.recordedAt,
              );
            }
          }
          await tx.execute(
            'INSERT INTO outbox (outbox_id, event_id, destination, envelope_json, '
            'sensitivity, state, attempt_count, created_at) '
            "VALUES (?, ?, ?, ?, ?, 'pending', 0, ?)",
            <Object?>[
              'event:${event.eventId}:$outboxDestination',
              event.eventId,
              outboxDestination,
              EventEnvelopeJsonCodec.encodeString(event),
              event.sensitivity.name.toUpperCase(),
              event.recordedAt.toUtc().toIso8601String(),
            ],
          );
        }
      });
    } on PersistenceException {
      rethrow;
    } on EventCodecException {
      throw const PersistenceException.invalidEvent();
    } on Object {
      throw const PersistenceException.transactionFailed();
    }
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async {
    try {
      final rows = await _database.query(
        'SELECT e.*, (SELECT json_group_array(json_object('
        "'type', s.subject_type, 'id', s.subject_id, "
        "'revision', s.subject_revision, 'ordinal', s.subject_ordinal)) "
        'FROM event_subjects s WHERE s.event_id = e.event_id) '
        'AS subject_refs_json '
        'FROM event_log e WHERE e.event_id = ? LIMIT 1',
        <Object?>[eventId],
      );
      return rows.isEmpty ? null : _decodeRow(rows.single);
    } on PersistenceException {
      rethrow;
    } on Object {
      throw const PersistenceException.readFailed();
    }
  }

  @override
  Future<List<EventEnvelope>> readBySubject(ObjectRef subject, {int? limit}) async {
    if (limit != null && limit <= 0) return const <EventEnvelope>[];
    try {
      final sql = 'SELECT e.*, (SELECT json_group_array(json_object('
          "'type', x.subject_type, 'id', x.subject_id, "
          "'revision', x.subject_revision, 'ordinal', x.subject_ordinal)) "
          'FROM event_subjects x WHERE x.event_id = e.event_id) '
          'AS subject_refs_json '
          'FROM event_log e JOIN event_subjects s ON s.event_id = e.event_id '
          'WHERE s.subject_type = ? AND s.subject_id = ? '
          'ORDER BY e.recorded_at ASC, e.sequence_no ASC'
          '${limit == null ? '' : ' LIMIT ?'}';
      final parameters = <Object?>[
        subject.type,
        subject.id.value,
        if (limit != null) limit,
      ];
      return (await _database.query(sql, parameters)).map(_decodeRow).toList();
    } on PersistenceException {
      rethrow;
    } on Object {
      throw const PersistenceException.readFailed();
    }
  }

  static void _validate(EventEnvelope event) {
    if (event.sensitivity == Sensitivity.d4) {
      throw const VaultSchemaViolation.d4();
    }
    VaultPersistenceValidator.validateSensitivity(
      event.sensitivity.name.toUpperCase(),
    );
    final encoded = EventEnvelopeJsonCodec.encode(event);
    VaultPersistenceValidator.rejectForbiddenSecretFields(encoded);
    if (event.subjectRefs.isEmpty) {
      throw EventAppendConflict(ReductionReason.missingSubject);
    }
  }

  static List<EventEnvelope> _deduplicateBatch(List<EventEnvelope> events) {
    final byId = <String, EventEnvelope>{};
    for (final event in events) {
      final prior = byId[event.eventId];
      if (prior == null) {
        byId[event.eventId] = event;
      } else if (!_sameEventContentForIdempotency(prior, event)) {
        throw EventAppendConflict(PersistenceErrorCode.eventConflict);
      }
    }
    return List<EventEnvelope>.unmodifiable(byId.values);
  }
}

bool _sameEventContentForIdempotency(
  EventEnvelope left,
  EventEnvelope right,
) =>
    EventEnvelopeJsonCodec.encodeString(_idempotencyEvent(left)) ==
    EventEnvelopeJsonCodec.encodeString(_idempotencyEvent(right));

/// The expected projection revision is an optimistic-concurrency guard, not
/// part of the event's identity. A retry may carry a newly computed guard
/// while still representing the same append.
EventEnvelope _idempotencyEvent(EventEnvelope event) {
  final payload = Map<String, Object?>.of(event.payload)
    ..remove('expected_revision');
  return EventEnvelope(
    eventId: event.eventId,
    eventType: event.eventType,
    eventVersion: event.eventVersion,
    occurredAt: event.occurredAt,
    recordedAt: event.recordedAt,
    actor: event.actor,
    subjectRefs: event.subjectRefs,
    correlationId: event.correlationId,
    causationId: event.causationId,
    sourceRefs: event.sourceRefs,
    consentRefs: event.consentRefs,
    sensitivity: event.sensitivity,
    payload: payload,
    integrity: event.integrity,
    extensions: event.extensions,
  );
}

Set<ObjectRef> _projectionSubjects(EventEnvelope event) {
  final byKey = <String, ObjectRef>{
    for (final ref in event.subjectRefs) '${ref.type}:${ref.id.value}': ref,
  };
  final erased = event.payload['erased_refs'];
  if (erased is List) {
    for (final value in erased.whereType<String>()) {
      final separator = value.indexOf(':');
      if (separator <= 0 || separator == value.length - 1) continue;
      final ref = ObjectRef(
        type: value.substring(0, separator),
        id: EntityId(value.substring(separator + 1)),
      );
      byKey['${ref.type}:${ref.id.value}'] = ref;
    }
  }
  return byKey.values.toSet();
}

Future<void> _writeProjection(
  SqlTransaction tx,
  ObjectProjection projection,
  int expectedRevision,
  String sensitivity,
  DateTime updatedAt,
) async {
  final state = ObjectProjectionJsonCodec.encodeString(projection);
  final time = updatedAt.toUtc().toIso8601String();
  if (expectedRevision == 0) {
    final changed = await tx.execute(
      'INSERT INTO projections (projection_type, subject_type, subject_id, '
      'revision, last_event_id, state_json, sensitivity, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>['core', projection.objectType, projection.id.value,
        projection.revision.value, projection.lastEventId, state, sensitivity, time],
    );
    if (changed != 1) {
      throw EventAppendConflict(ReductionReason.revisionConflict);
    }
  } else {
    final changed = await tx.execute(
      'UPDATE projections SET revision = ?, last_event_id = ?, state_json = ?, '
      'sensitivity = ?, updated_at = ? WHERE projection_type = ? '
      'AND subject_type = ? AND subject_id = ? AND revision = ?',
      <Object?>[projection.revision.value, projection.lastEventId, state,
        sensitivity, time, 'core', projection.objectType, projection.id.value,
        expectedRevision],
    );
    if (changed != 1) {
      throw EventAppendConflict(ReductionReason.revisionConflict);
    }
  }
}

const _insertEventSql = 'INSERT INTO event_log (event_id, event_type, '
    'event_version, occurred_at, recorded_at, actor_json, correlation_id, '
    'causation_id, source_refs_json, consent_refs_json, sensitivity, '
    'payload_json, integrity_json, extensions_json) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

const _selectEventByIdSql = 'SELECT e.*, (SELECT json_group_array(json_object('
    "'type', s.subject_type, 'id', s.subject_id, "
    "'revision', s.subject_revision, 'ordinal', s.subject_ordinal)) "
    'FROM event_subjects s WHERE s.event_id = e.event_id) '
    'AS subject_refs_json '
    'FROM event_log e WHERE e.event_id = ? LIMIT 1';

List<Object?> _eventParameters(Map<String, Object?> e) => <Object?>[
  e['event_id'], e['event_type'], e['event_version'], e['occurred_at'],
  e['recorded_at'], jsonEncode(e['actor']), e['correlation_id'],
  e['causation_id'], jsonEncode(e['source_refs']), jsonEncode(e['consent_refs']),
  (e['sensitivity']! as String).toUpperCase(), jsonEncode(e['payload']),
  jsonEncode(e['integrity']), jsonEncode(e['extensions']),
];

EventEnvelope _decodeRow(SqlRow row) {
  final rawRefs = jsonDecode((row['subject_refs_json'] as String?) ?? '[]') as List;
  final refs = rawRefs
      .map((value) => Map<String, Object?>.from(value as Map))
      .toList()
    ..sort((a, b) =>
        (a['ordinal']! as int).compareTo(b['ordinal']! as int));
  for (final ref in refs) {
    ref.remove('ordinal');
    if (ref['revision'] == null) ref.remove('revision');
  }
  return EventEnvelopeJsonCodec.decode(<String, Object?>{
    'schema_version': 1,
    'event_id': row['event_id'],
    'event_type': row['event_type'],
    'event_version': row['event_version'],
    'occurred_at': row['occurred_at'],
    'recorded_at': row['recorded_at'],
    'actor': jsonDecode(row['actor_json']! as String),
    'subject_refs': refs,
    'correlation_id': row['correlation_id'],
    if (row['causation_id'] != null) 'causation_id': row['causation_id'],
    'source_refs': jsonDecode(row['source_refs_json']! as String),
    'consent_refs': jsonDecode(row['consent_refs_json']! as String),
    'sensitivity': (row['sensitivity']! as String).toLowerCase(),
    'payload': jsonDecode(row['payload_json']! as String),
    'integrity': jsonDecode(row['integrity_json']! as String),
    'extensions': jsonDecode(row['extensions_json']! as String),
  });
}
