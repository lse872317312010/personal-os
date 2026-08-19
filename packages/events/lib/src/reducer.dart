import 'package:personal_os_domain/domain.dart';

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
}

final class ObjectProjection {
  const ObjectProjection({
    required this.objectType,
    required this.id,
    required this.revision,
    required this.state,
    required this.lastEventId,
  });

  final String objectType;
  final EntityId id;
  final Revision revision;
  final String state;
  final String lastEventId;
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
      event.payload['execution_record_ref'] == null) {
    return _rejected(
      projections,
      seenEventIds,
      ReductionReason.missingExecutionRecord,
    );
  }

  final nextProjection = ObjectProjection(
    objectType: subject.type,
    id: subject.id,
    revision: (current?.revision ?? const Revision(0)).next,
    state: transition,
    lastEventId: event.eventId,
  );
  return ReductionResult(
    disposition: ReductionDisposition.applied,
    projections: Map<String, ObjectProjection>.unmodifiable(
      <String, ObjectProjection>{...projections, key: nextProjection},
    ),
    seenEventIds: Set<String>.unmodifiable(<String>{
      ...seenEventIds,
      event.eventId,
    }),
  );
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
      EventTypes.reviewAccepted when from == ReviewState.userReviewed.name =>
        ReviewState.accepted.name,
      EventTypes.reviewRejected when from == ReviewState.userReviewed.name =>
        ReviewState.rejected.name,
      _ => null,
    };

const _knownTypes = <String>{
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
  EventTypes.taskCompleted,
  EventTypes.taskSkipped,
  EventTypes.taskFailed,
  EventTypes.taskStopped,
  EventTypes.consentRequested,
  EventTypes.consentGranted,
  EventTypes.consentRevoked,
  EventTypes.consentExpired,
  EventTypes.reviewCreated,
  EventTypes.reviewAccepted,
  EventTypes.reviewRejected,
};

