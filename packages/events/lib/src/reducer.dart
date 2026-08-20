import 'package:personal_os_domain/domain.dart';

import 'deep_freeze.dart';
import 'event_envelope.dart';
import 'event_types.dart';

enum ReductionDisposition { applied, duplicate, rejected, quarantined }

abstract final class ReductionReason {
  static const duplicateEvent = 'duplicate_event';
  static const unsupportedEventVersion = 'unsupported_event_version';
  static const unsupportedEventType = 'unsupported_event_type';
  static const missingSubject = 'missing_subject';
  static const revisionConflict = 'revision_conflict';
  static const illegalStateTransition = 'illegal_state_transition';
  static const missingExecutionRecord = 'missing_execution_record';
  static const invalidDeletionTombstone = 'invalid_deletion_tombstone';
}

final class ObjectProjection {
  ObjectProjection({
    required this.objectType,
    required this.id,
    required this.revision,
    required this.state,
    required this.lastEventId,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) : attributes = deepFreezeMap(attributes);

  final String objectType;
  final EntityId id;
  final Revision revision;
  final String state;
  final String lastEventId;
  final Map<String, Object?> attributes;
}

final class ReductionResult {
  const ReductionResult({
    required this.disposition,
    required this.projections,
    required this.seenEventIds,
    this.reasonCode,
  });

  final ReductionDisposition disposition;
  final Map<String, ObjectProjection> projections;
  final Set<String> seenEventIds;
  final String? reasonCode;
}

/// Deterministic minimum reducer for M1 lifecycle events.
///
/// Authorization, Consent validity, sensitivity policy, late-event interval
/// replay and conflict resolution belong to policy/application projections and
/// must run before or around this reducer. Rejected and quarantined events do
/// not mutate projections. Accepted event IDs are retained for idempotency.
ReductionResult reduceCore({
  required Map<String, ObjectProjection> projections,
  required Set<String> seenEventIds,
  required EventEnvelope event,
}) {
  if (seenEventIds.contains(event.eventId)) {
    return ReductionResult(
      disposition: ReductionDisposition.duplicate,
      projections: projections,
      seenEventIds: seenEventIds,
      reasonCode: ReductionReason.duplicateEvent,
    );
  }

  if (event.eventVersion != 1) {
    return ReductionResult(
      disposition: ReductionDisposition.quarantined,
      projections: projections,
      seenEventIds: seenEventIds,
      reasonCode: ReductionReason.unsupportedEventVersion,
    );
  }

  if (event.subjectRefs.isEmpty) {
    return _rejected(projections, seenEventIds, ReductionReason.missingSubject);
  }

  final subject = event.subjectRefs.first;
  final key = '${subject.type}:${subject.id.value}';
  final current = projections[key];
  final expected = event.expectedRevision;
  if (expected != null && expected != (current?.revision.value ?? 0)) {
    return _rejected(
      projections,
      seenEventIds,
      ReductionReason.revisionConflict,
    );
  }

  final transition = _transition(event, current?.state);
  if (transition == null) {
    final knownType = _knownTypes.contains(event.eventType);
    return _rejected(
      projections,
      seenEventIds,
      knownType
          ? ReductionReason.illegalStateTransition
          : ReductionReason.unsupportedEventType,
    );
  }

  if (event.eventType == EventTypes.taskCompleted &&
      event.payload['execution_record_ref'] == null &&
      event.payload['execution_ref'] == null) {
    return _rejected(
      projections,
      seenEventIds,
      ReductionReason.missingExecutionRecord,
    );
  }

  final nextProjection = ObjectProjection(
    objectType: subject.type,
    id: subject.id,
    revision: (current?.revision ?? Revision(0)).next,
    state: transition,
    lastEventId: event.eventId,
  );
  var nextProjections = <String, ObjectProjection>{
    ...projections,
    key: nextProjection,
  };
  if (event.eventType == EventTypes.deletionRequested) {
    nextProjections = _markDeletionSubjects(
      nextProjections,
      event.subjectRefs.skip(1),
      event,
      'unavailable_pending_deletion',
    );
  } else if (event.eventType == EventTypes.deletionCompleted) {
    if (event.payload['contains_content_hash'] != false ||
        event.payload['tombstone_id'] == null) {
      return _rejected(
        projections,
        seenEventIds,
        ReductionReason.invalidDeletionTombstone,
      );
    }
    nextProjections = _markErasedRefs(nextProjections, event);
    nextProjections = _projectSafeTombstone(nextProjections, event);
  }
  return ReductionResult(
    disposition: ReductionDisposition.applied,
    projections: Map<String, ObjectProjection>.unmodifiable(
      nextProjections,
    ),
    seenEventIds: Set<String>.unmodifiable(<String>{
      ...seenEventIds,
      event.eventId,
    }),
  );
}

Map<String, ObjectProjection> _projectSafeTombstone(
  Map<String, ObjectProjection> projections,
  EventEnvelope event,
) {
  final tombstone = event.subjectRefs
      .where((subject) => subject.type == 'tombstone')
      .firstOrNull;
  if (tombstone == null) return projections;
  final key = 'tombstone:${tombstone.id.value}';
  return <String, ObjectProjection>{
    ...projections,
    key: ObjectProjection(
      objectType: tombstone.type,
      id: tombstone.id,
      revision: Revision(1),
      state: 'recorded',
      lastEventId: event.eventId,
      attributes: const <String, Object?>{'contains_content_hash': false},
    ),
  };
}

Map<String, ObjectProjection> _markDeletionSubjects(
  Map<String, ObjectProjection> projections,
  Iterable<ObjectRef> subjects,
  EventEnvelope event,
  String state,
) {
  final result = <String, ObjectProjection>{...projections};
  for (final subject in subjects) {
    final key = '${subject.type}:${subject.id.value}';
    final current = result[key];
    result[key] = ObjectProjection(
      objectType: subject.type,
      id: subject.id,
      revision: (current?.revision ?? Revision(0)).next,
      state: state,
      lastEventId: event.eventId,
    );
  }
  return result;
}

Map<String, ObjectProjection> _markErasedRefs(
  Map<String, ObjectProjection> projections,
  EventEnvelope event,
) {
  final raw = event.payload['erased_refs'];
  if (raw is! List) return projections;
  final refs = raw.whereType<String>().map(_parseLooseRef).whereType<ObjectRef>();
  return _markDeletionSubjects(projections, refs, event, 'deleted');
}

ObjectRef? _parseLooseRef(String value) {
  final separator = value.indexOf(':');
  if (separator <= 0 || separator == value.length - 1) return null;
  return ObjectRef(
    type: value.substring(0, separator),
    id: EntityId(value.substring(separator + 1)),
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

ReductionResult _rejected(
  Map<String, ObjectProjection> projections,
  Set<String> seenEventIds,
  String reason,
) =>
    ReductionResult(
      disposition: ReductionDisposition.rejected,
      projections: projections,
      seenEventIds: seenEventIds,
      reasonCode: reason,
    );

String? _transition(EventEnvelope event, String? from) => switch (event.eventType) {
      EventTypes.sourceRegistered when from == null => 'registered',
      EventTypes.observationRecorded when from == null => 'recorded',
      EventTypes.baselineCreated when from == null => 'created',
      EventTypes.opportunityIdentified when from == null => 'identified',
      EventTypes.recommendationCreated when from == null => 'created',
      EventTypes.executionRecorded when from == null => 'recorded',
      EventTypes.outcomeRecorded when from == null => 'recorded',
      EventTypes.constraintRecorded when from == null => 'recorded',
      EventTypes.claimProposed when from == null => ClaimState.proposed.name,
      EventTypes.claimConfirmed when from == ClaimState.proposed.name =>
        ClaimState.confirmed.name,
      EventTypes.claimDisputed
          when from == ClaimState.proposed.name ||
              from == ClaimState.confirmed.name =>
        ClaimState.disputed.name,
      EventTypes.claimExpired
          when from == ClaimState.proposed.name ||
              from == ClaimState.confirmed.name ||
              from == ClaimState.disputed.name =>
        ClaimState.expired.name,
      EventTypes.claimWithdrawn
          when from == ClaimState.proposed.name ||
              from == ClaimState.confirmed.name ||
              from == ClaimState.disputed.name =>
        ClaimState.withdrawn.name,
      EventTypes.goalCreated when from == null => GoalState.draft.name,
      EventTypes.goalActivated
          when from == GoalState.draft.name || from == GoalState.paused.name =>
        GoalState.active.name,
      EventTypes.goalPaused when from == GoalState.active.name =>
        GoalState.paused.name,
      EventTypes.goalCompleted when from == GoalState.active.name =>
        GoalState.achieved.name,
      EventTypes.planDrafted when from == null => PlanState.draft.name,
      EventTypes.planApproved when from == PlanState.draft.name =>
        PlanState.approved.name,
      EventTypes.planActivated
          when from == PlanState.approved.name || from == PlanState.paused.name =>
        PlanState.active.name,
      EventTypes.planPaused when from == PlanState.active.name =>
        PlanState.paused.name,
      EventTypes.planCompleted when from == PlanState.active.name =>
        PlanState.completed.name,
      EventTypes.planStopped
          when from == PlanState.approved.name ||
              from == PlanState.active.name ||
              from == PlanState.paused.name =>
        PlanState.stopped.name,
      EventTypes.taskPlanned when from == null => TaskState.planned.name,
      EventTypes.taskReady when from == TaskState.planned.name =>
        TaskState.ready.name,
      EventTypes.taskInProgress when from == TaskState.ready.name =>
        TaskState.inProgress.name,
      EventTypes.taskCompleted
          when from == TaskState.planned.name ||
              from == TaskState.ready.name ||
              from == TaskState.inProgress.name =>
        TaskState.completed.name,
      EventTypes.taskSkipped
          when from == TaskState.planned.name || from == TaskState.ready.name =>
        TaskState.skipped.name,
      EventTypes.taskFailed when from == TaskState.inProgress.name =>
        TaskState.failed.name,
      EventTypes.taskStopped
          when from == TaskState.planned.name ||
              from == TaskState.ready.name ||
              from == TaskState.inProgress.name =>
        TaskState.stopped.name,
      EventTypes.consentRequested when from == null => ConsentState.requested.name,
      EventTypes.consentGranted when from == ConsentState.requested.name =>
        ConsentState.granted.name,
      EventTypes.consentRevoked when from == ConsentState.granted.name =>
        ConsentState.revoked.name,
      EventTypes.consentExpired when from == ConsentState.granted.name =>
        ConsentState.expired.name,
      EventTypes.reviewCreated when from == null => ReviewState.draft.name,
      EventTypes.reviewUserReviewed when from == ReviewState.draft.name =>
        ReviewState.userReviewed.name,
      EventTypes.reviewAccepted when from == ReviewState.userReviewed.name =>
        ReviewState.accepted.name,
      EventTypes.reviewRejected when from == ReviewState.userReviewed.name =>
        ReviewState.rejected.name,
      EventTypes.modelRevisionProposed when from == null => 'proposed',
      EventTypes.modelRevisionAccepted when from == 'proposed' => 'accepted',
      EventTypes.deletionRequested when from == null => 'requested',
      EventTypes.deletionCompleted when from == 'requested' => 'completed',
      EventTypes.conflictDetected when from == null => 'unresolved',
      EventTypes.conflictResolutionProposed when from == 'unresolved' =>
        'resolution_proposed',
      EventTypes.conflictResolved
          when from == 'unresolved' || from == 'resolution_proposed' =>
        'resolved',
      EventTypes.conflictDismissed
          when from == 'unresolved' || from == 'resolution_proposed' =>
        'dismissed',
      _ => null,
    };

const _knownTypes = <String>{
  EventTypes.sourceRegistered,
  EventTypes.observationRecorded,
  EventTypes.baselineCreated,
  EventTypes.opportunityIdentified,
  EventTypes.recommendationCreated,
  EventTypes.executionRecorded,
  EventTypes.outcomeRecorded,
  EventTypes.constraintRecorded,
  EventTypes.claimProposed,
  EventTypes.claimConfirmed,
  EventTypes.claimDisputed,
  EventTypes.claimExpired,
  EventTypes.claimWithdrawn,
  EventTypes.goalCreated,
  EventTypes.goalActivated,
  EventTypes.goalPaused,
  EventTypes.goalCompleted,
  EventTypes.planDrafted,
  EventTypes.planApproved,
  EventTypes.planActivated,
  EventTypes.planPaused,
  EventTypes.planCompleted,
  EventTypes.planStopped,
  EventTypes.taskPlanned,
  EventTypes.taskReady,
  EventTypes.taskInProgress,
  EventTypes.taskCompleted,
  EventTypes.taskSkipped,
  EventTypes.taskFailed,
  EventTypes.taskStopped,
  EventTypes.consentRequested,
  EventTypes.consentGranted,
  EventTypes.consentRevoked,
  EventTypes.consentExpired,
  EventTypes.reviewCreated,
  EventTypes.reviewUserReviewed,
  EventTypes.reviewAccepted,
  EventTypes.reviewRejected,
  EventTypes.modelRevisionProposed,
  EventTypes.modelRevisionAccepted,
  EventTypes.deletionRequested,
  EventTypes.deletionCompleted,
  EventTypes.conflictDetected,
  EventTypes.conflictResolutionProposed,
  EventTypes.conflictResolved,
  EventTypes.conflictDismissed,
};
