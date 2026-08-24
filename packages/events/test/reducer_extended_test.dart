import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:test/test.dart';

void main() {
  test('S1 point-in-time objects are projected without invented lifecycles', () {
    for (final entry in <(String, String, String)>[
      (EventTypes.sourceRegistered, 'source', 'registered'),
      (EventTypes.observationRecorded, 'observation', 'recorded'),
      (EventTypes.baselineCreated, 'baseline', 'created'),
      (EventTypes.opportunityIdentified, 'opportunity', 'identified'),
      (EventTypes.recommendationCreated, 'recommendation', 'created'),
    ]) {
      final result = _reduce(_event(entry.$1, entry.$2));
      expect(result.disposition, ReductionDisposition.applied);
      expect(result.projections['${entry.$2}:1']?.state, entry.$3);
    }
  });

  test('S2 task and review intermediate transitions are explicit', () {
    var projections = <String, ObjectProjection>{};
    var seen = <String>{};
    for (final type in <String>[
      EventTypes.taskPlanned,
      EventTypes.taskReady,
      EventTypes.taskInProgress,
    ]) {
      final result = reduceCore(
        projections: projections,
        seenEventIds: seen,
        event: _event(type, 'task', id: 'T1'),
      );
      expect(result.disposition, ReductionDisposition.applied);
      projections = result.projections;
      seen = result.seenEventIds;
    }
    final completed = reduceCore(
      projections: projections,
      seenEventIds: seen,
      event: _event(
        EventTypes.taskCompleted,
        'task',
        id: 'T1',
        payload: const {'execution_ref': 'execution:E1'},
      ),
    );
    expect(completed.projections['task:T1']?.state, 'completed');

    projections = <String, ObjectProjection>{};
    seen = <String>{};
    for (final type in <String>[
      EventTypes.reviewCreated,
      EventTypes.reviewUserReviewed,
      EventTypes.reviewAccepted,
    ]) {
      final result = reduceCore(
        projections: projections,
        seenEventIds: seen,
        event: _event(type, 'review', id: 'R1'),
      );
      expect(result.disposition, ReductionDisposition.applied);
      projections = result.projections;
      seen = result.seenEventIds;
    }
    expect(projections['review:R1']?.state, 'accepted');
  });

  test('consent can be revoked and granted again with a new revision', () {
    var projections = <String, ObjectProjection>{};
    var seen = <String>{};
    for (final entry in <(String, int)>[
      (EventTypes.consentRequested, 0),
      (EventTypes.consentGranted, 1),
      (EventTypes.consentRevoked, 2),
      (EventTypes.consentRequested, 3),
      (EventTypes.consentGranted, 4),
    ]) {
      final result = reduceCore(
        projections: projections,
        seenEventIds: seen,
        event: _event(
          entry.$1,
          'consent',
          id: 'C1',
          payload: <String, Object?>{'expected_revision': entry.$2},
        ),
      );
      expect(result.disposition, ReductionDisposition.applied);
      projections = result.projections;
      seen = result.seenEventIds;
    }
    expect(projections['consent:C1']?.state, ConsentState.granted.name);
    expect(projections['consent:C1']?.revision.value, 5);
  });

  test('deletion barrier marks scope and completion marks erased refs deleted', () {
    final requested = _reduce(
      _event(
        EventTypes.deletionRequested,
        'deletion',
        id: 'DR1',
        additionalSubjects: <ObjectRef>[_ref('source', 'S1')],
      ),
    );
    expect(requested.projections['deletion:DR1']?.state, 'requested');
    expect(
      requested.projections['source:S1']?.state,
      'unavailable_pending_deletion',
    );

    final completed = reduceCore(
      projections: requested.projections,
      seenEventIds: requested.seenEventIds,
      event: _event(
        EventTypes.deletionCompleted,
        'deletion',
        id: 'DR1',
        additionalSubjects: <ObjectRef>[_ref('tombstone', 'TS1')],
        payload: const <String, Object?>{
          'tombstone_id': 'TS1',
          'contains_content_hash': false,
          'erased_refs': <String>['source:S1', 'blob:S1-raw'],
        },
      ),
    );
    expect(completed.disposition, ReductionDisposition.applied);
    expect(completed.projections['source:S1']?.state, 'deleted');
    expect(completed.projections['blob:S1-raw']?.state, 'deleted');
    expect(
      completed.projections['tombstone:TS1']?.attributes['contains_content_hash'],
      isFalse,
    );
  });

  test('unsafe deletion completion is rejected without mutation', () {
    final requested = _reduce(
      _event(EventTypes.deletionRequested, 'deletion', id: 'DR1'),
    );
    final result = reduceCore(
      projections: requested.projections,
      seenEventIds: requested.seenEventIds,
      event: _event(
        EventTypes.deletionCompleted,
        'deletion',
        id: 'DR1',
        payload: const <String, Object?>{
          'tombstone_id': 'TS1',
          'contains_content_hash': true,
        },
      ),
    );
    expect(result.disposition, ReductionDisposition.rejected);
    expect(result.reasonCode, ReductionReason.invalidDeletionTombstone);
    expect(result.projections['deletion:DR1']?.state, 'requested');
  });

  test('explicit conflict lifecycle does not alter the conflicted object', () {
    final plan = ObjectProjection(
      objectType: 'plan',
      id: EntityId('P1'),
      revision: Revision(3),
      state: 'active',
      lastEventId: 'old',
    );
    final detected = reduceCore(
      projections: <String, ObjectProjection>{'plan:P1': plan},
      seenEventIds: <String>{},
      event: _event(EventTypes.conflictDetected, 'conflict', id: 'CF1'),
    );
    expect(detected.projections['conflict:CF1']?.state, 'unresolved');
    expect(detected.projections['plan:P1'], same(plan));
  });

  test('unknown semantic event is rejected and unsupported version quarantined', () {
    final unknown = _reduce(_event('future.semantic', 'future'));
    expect(unknown.disposition, ReductionDisposition.rejected);
    expect(unknown.reasonCode, ReductionReason.unsupportedEventType);

    final future = _reduce(_event(EventTypes.sourceRegistered, 'source', version: 2));
    expect(future.disposition, ReductionDisposition.quarantined);
    expect(future.reasonCode, ReductionReason.unsupportedEventVersion);
  });
}

ReductionResult _reduce(EventEnvelope event) => reduceCore(
      projections: <String, ObjectProjection>{},
      seenEventIds: <String>{},
      event: event,
    );

EventEnvelope _event(
  String type,
  String subjectType, {
  String id = '1',
  int version = 1,
  Map<String, Object?> payload = const <String, Object?>{},
  List<ObjectRef> additionalSubjects = const <ObjectRef>[],
}) =>
    EventEnvelope(
      eventId: '$type-$id-${payload['expected_revision'] ?? version}-$version',
      eventType: type,
      eventVersion: version,
      occurredAt: DateTime.utc(2026, 8, 20),
      recordedAt: DateTime.utc(2026, 8, 20),
      actor: ActorRef(
        actorId: 'user:self',
        actorType: ActorType.user,
        authoritySource: 'test',
      ),
      correlationId: 'test',
      sensitivity: Sensitivity.d1,
      subjectRefs: <ObjectRef>[_ref(subjectType, id), ...additionalSubjects],
      payload: payload,
    );

ObjectRef _ref(String type, String id) =>
    ObjectRef(type: type, id: EntityId(id));
