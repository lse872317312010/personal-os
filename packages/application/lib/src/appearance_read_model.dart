import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'appearance_queries.dart';

/// The part of the appearance vertical slice that can be reconstructed from
/// profile-scoped events. This is deliberately a read model, not a second
/// source of truth: the event list remains the authoritative input.
final class AppearanceSessionView {
  const AppearanceSessionView({
    required this.profileId,
    required this.events,
    required this.claims,
    required this.goal,
    required this.plan,
    required this.tasks,
    required this.review,
    required this.consent,
    this.observations = const <AppearanceObservationView>[],
  });

  final EntityId profileId;
  final List<EventEnvelope> events;
  final List<AppearanceClaimView> claims;
  final AppearanceGoalView? goal;
  final AppearancePlanView? plan;
  final List<AppearanceTaskView> tasks;
  final AppearanceReviewView? review;
  final AppearanceConsentView? consent;
  final List<AppearanceObservationView> observations;

  bool get hasAnalysis => claims.isNotEmpty;
  bool get hasPlan => plan != null;
}

/// Safe, opaque metadata projected from an observation event.
///
/// The read model intentionally does not expose the event payload or consult
/// controller/blob state. The blob reference is only an opaque locator.
final class AppearanceObservationView {
  const AppearanceObservationView({
    required this.id,
    required this.blobRef,
    required this.mediaType,
    required this.context,
    required this.eventId,
  });

  final String id;
  final String blobRef;
  final String mediaType;
  final String context;
  final String eventId;
}

final class AppearanceClaimView {
  const AppearanceClaimView({
    required this.id,
    required this.state,
    this.dimension,
    this.statement,
    this.confidence,
    this.evidenceBlobRef,
  });

  final String id;
  final String state;
  final String? dimension;
  final String? statement;
  final double? confidence;
  final String? evidenceBlobRef;

  AppearanceClaimView withState(String nextState) => AppearanceClaimView(
        id: id,
        state: nextState,
        dimension: dimension,
        statement: statement,
        confidence: confidence,
        evidenceBlobRef: evidenceBlobRef,
      );
}

final class AppearanceGoalView {
  const AppearanceGoalView({
    required this.id,
    required this.state,
    this.title,
    this.claimRefs = const <String>[],
  });

  final String id;
  final String state;
  final String? title;
  final List<String> claimRefs;

  AppearanceGoalView withState(String nextState) => AppearanceGoalView(
        id: id,
        state: nextState,
        title: title,
        claimRefs: claimRefs,
      );
}

final class AppearancePlanView {
  const AppearancePlanView({
    required this.id,
    required this.state,
    this.goalRef,
    this.title,
  });

  final String id;
  final String state;
  final String? goalRef;
  final String? title;

  AppearancePlanView withState(String nextState) => AppearancePlanView(
        id: id,
        state: nextState,
        goalRef: goalRef,
        title: title,
      );
}

final class AppearanceTaskView {
  const AppearanceTaskView({
    required this.id,
    required this.state,
    this.planRef,
    this.title,
    this.rationale,
  });

  final String id;
  final String state;
  final String? planRef;
  final String? title;
  final String? rationale;

  AppearanceTaskView withState(String nextState) => AppearanceTaskView(
        id: id,
        state: nextState,
        planRef: planRef,
        title: title,
        rationale: rationale,
      );
}

final class AppearanceReviewView {
  const AppearanceReviewView({required this.id, required this.state});

  final String id;
  final String state;

  AppearanceReviewView withState(String nextState) =>
      AppearanceReviewView(id: id, state: nextState);
}

final class AppearanceConsentView {
  const AppearanceConsentView({
    required this.id,
    required this.state,
    required this.stateRevision,
    required this.consentRevision,
  });

  final String id;
  final String state;
  final int stateRevision;
  final int consentRevision;

  AppearanceConsentView withState({
    required String nextState,
    required int nextStateRevision,
    int? nextConsentRevision,
  }) =>
      AppearanceConsentView(
        id: id,
        state: nextState,
        stateRevision: nextStateRevision,
        consentRevision: nextConsentRevision ?? consentRevision,
      );
}

final class AppearanceSessionQueryHandler {
  const AppearanceSessionQueryHandler(this._eventStore);

  final EventStore _eventStore;

  /// Rebuilds the appearance view from the profile subject stream.
  ///
  /// This deliberately does not read controller state or adapter-specific
  /// projections. Legacy task/review events without a profile reference are
  /// still accepted when supplied by a broader history query, while new
  /// feedback commands may link them to the profile stream.
  Future<AppearanceSessionView> execute(
    GetAppearanceHistoryQuery query,
  ) async {
    final events = await _eventStore.readBySubject(
      ObjectRef(type: 'profile', id: query.profileId),
      limit: query.limit,
    );
    final claims = <String, AppearanceClaimView>{};
    AppearanceGoalView? goal;
    AppearancePlanView? plan;
    final tasks = <String, AppearanceTaskView>{};
    final observations = <String, AppearanceObservationView>{};
    AppearanceReviewView? review;
    AppearanceConsentView? consent;

    for (final event in events) {
      final subject = _subjectForEvent(event);
      if (subject == null) continue;
      final id = subject.id.value;
      final payload = event.payload;
      switch (event.eventType) {
        case EventTypes.observationRecorded:
          final observation = _safeObservation(
            event,
            profileId: query.profileId,
          );
          if (observation != null) observations[observation.id] = observation;
          break;
        case EventTypes.claimProposed:
          claims[id] = AppearanceClaimView(
            id: id,
            state: ClaimState.proposed.name,
            dimension: _string(payload['dimension']),
            statement: _string(payload['statement']),
            confidence: _double(payload['confidence']),
            evidenceBlobRef: _string(payload['evidence_blob_ref']),
          );
          break;
        case EventTypes.claimConfirmed:
          claims[id] = _claimState(claims[id], id, ClaimState.confirmed.name);
          break;
        case EventTypes.claimDisputed:
          claims[id] = _claimState(claims[id], id, ClaimState.disputed.name);
          break;
        case EventTypes.claimExpired:
          claims[id] = _claimState(claims[id], id, ClaimState.expired.name);
          break;
        case EventTypes.claimWithdrawn:
          claims[id] = _claimState(claims[id], id, ClaimState.withdrawn.name);
          break;
        case EventTypes.goalCreated:
          goal = AppearanceGoalView(
            id: id,
            state: GoalState.draft.name,
            title: _string(payload['title']),
            claimRefs: _strings(payload['claim_refs']),
          );
          break;
        case EventTypes.goalActivated:
          goal = _goalState(goal, id, GoalState.active.name);
          break;
        case EventTypes.goalPaused:
          goal = _goalState(goal, id, GoalState.paused.name);
          break;
        case EventTypes.goalCompleted:
          goal = _goalState(goal, id, GoalState.achieved.name);
          break;
        case EventTypes.planDrafted:
          plan = AppearancePlanView(
            id: id,
            state: PlanState.draft.name,
            goalRef: _string(payload['goal_ref']),
            title: _string(payload['title']),
          );
          break;
        case EventTypes.planApproved:
          plan = _planState(plan, id, PlanState.approved.name);
          break;
        case EventTypes.planActivated:
          plan = _planState(plan, id, PlanState.active.name);
          break;
        case EventTypes.planPaused:
          plan = _planState(plan, id, PlanState.paused.name);
          break;
        case EventTypes.planCompleted:
          plan = _planState(plan, id, PlanState.completed.name);
          break;
        case EventTypes.planStopped:
          plan = _planState(plan, id, PlanState.stopped.name);
          break;
        case EventTypes.taskPlanned:
          tasks[id] = AppearanceTaskView(
            id: id,
            state: TaskState.planned.name,
            planRef: _string(payload['plan_ref']),
            title: _string(payload['title']),
            rationale: _string(payload['rationale']),
          );
          break;
        case EventTypes.taskReady:
          tasks[id] = _taskState(tasks[id], id, TaskState.ready.name);
          break;
        case EventTypes.taskInProgress:
          tasks[id] = _taskState(tasks[id], id, TaskState.inProgress.name);
          break;
        case EventTypes.taskCompleted:
          if (subject.type == 'task') {
            tasks[id] = _taskState(tasks[id], id, TaskState.completed.name);
          }
          break;
        case EventTypes.taskSkipped:
          if (subject.type == 'task') {
            tasks[id] = _taskState(tasks[id], id, TaskState.skipped.name);
          }
          break;
        case EventTypes.taskFailed:
          tasks[id] = _taskState(tasks[id], id, TaskState.failed.name);
          break;
        case EventTypes.taskStopped:
          tasks[id] = _taskState(tasks[id], id, TaskState.stopped.name);
          break;
        case EventTypes.reviewCreated:
          if (subject.type == 'review') {
            review = AppearanceReviewView(
              id: id,
              state: ReviewState.draft.name,
            );
          }
          break;
        case EventTypes.reviewUserReviewed:
          if (subject.type == 'review') {
            review = _reviewState(review, id, ReviewState.userReviewed.name);
          }
          break;
        case EventTypes.reviewAccepted:
          if (subject.type == 'review') {
            review = _reviewState(review, id, ReviewState.accepted.name);
          }
          break;
        case EventTypes.reviewRejected:
          if (subject.type == 'review') {
            review = _reviewState(review, id, ReviewState.rejected.name);
          }
          break;
        case EventTypes.consentRequested:
          consent = AppearanceConsentView(
            id: id,
            state: ConsentState.requested.name,
            stateRevision: (event.expectedRevision ?? 0) + 1,
            consentRevision: _int(payload['consent_revision']) ?? 1,
          );
          break;
        case EventTypes.consentGranted:
          consent = _consentState(
            consent,
            id,
            ConsentState.granted.name,
            (event.expectedRevision ?? 1) + 1,
            _int(payload['consent_revision']),
          );
          break;
        case EventTypes.consentRevoked:
          consent = _consentState(
            consent,
            id,
            ConsentState.revoked.name,
            (consent?.stateRevision ?? 0) + 1,
            _int(payload['consent_revision']),
          );
          break;
        case EventTypes.consentExpired:
          consent = _consentState(
            consent,
            id,
            ConsentState.expired.name,
            (consent?.stateRevision ?? 0) + 1,
            _int(payload['consent_revision']),
          );
          break;
      }
    }

    return AppearanceSessionView(
      profileId: query.profileId,
      events: List<EventEnvelope>.unmodifiable(events),
      claims: List<AppearanceClaimView>.unmodifiable(claims.values),
      goal: goal,
      plan: plan,
      tasks: List<AppearanceTaskView>.unmodifiable(tasks.values),
      review: review,
      consent: consent,
      observations: List<AppearanceObservationView>.unmodifiable(
        observations.values,
      ),
    );
  }
}

AppearanceClaimView _claimState(
  AppearanceClaimView? current,
  String id,
  String state,
) =>
    (current ?? AppearanceClaimView(id: id, state: state)).withState(state);

AppearanceGoalView _goalState(
  AppearanceGoalView? current,
  String id,
  String state,
) =>
    (current ?? AppearanceGoalView(id: id, state: state)).withState(state);

AppearancePlanView _planState(
  AppearancePlanView? current,
  String id,
  String state,
) =>
    (current ?? AppearancePlanView(id: id, state: state)).withState(state);

AppearanceTaskView _taskState(
  AppearanceTaskView? current,
  String id,
  String state,
) =>
    (current ?? AppearanceTaskView(id: id, state: state)).withState(state);

AppearanceReviewView _reviewState(
  AppearanceReviewView? current,
  String id,
  String state,
) =>
    (current ?? AppearanceReviewView(id: id, state: state)).withState(state);

AppearanceConsentView _consentState(
  AppearanceConsentView? current,
  String id,
  String state,
  int stateRevision,
  int? consentRevision,
) =>
    (current ??
            AppearanceConsentView(
              id: id,
              state: state,
              stateRevision: stateRevision,
              consentRevision: consentRevision ?? 1,
            ))
        .withState(
      nextState: state,
      nextStateRevision: stateRevision,
      nextConsentRevision: consentRevision,
    );

String? _string(Object? value) => value is String ? value : null;

AppearanceObservationView? _safeObservation(
  EventEnvelope event, {
  required EntityId profileId,
}) {
  if (event.sensitivity == Sensitivity.d4 ||
      !event.subjectRefs.any(
        (ref) => ref.type == 'profile' && ref.id == profileId,
      )) {
    return null;
  }
  final observationRef = event.subjectRefs.firstWhereOrNull(
    (ref) => ref.type == 'observation',
  );
  final id = _string(event.payload['observation_id']);
  final blobRef = _string(event.payload['blob_ref']);
  final mediaType = _string(event.payload['media_type']);
  final context = _string(event.payload['observation_context']);
  if (observationRef == null ||
      id == null ||
      blobRef == null ||
      mediaType == null ||
      context == null ||
      id.trim().isEmpty ||
      id != observationRef.id.value ||
      !_validOpaqueBlobRef(blobRef) ||
      mediaType.trim().isEmpty ||
      context.trim().isEmpty) {
    return null;
  }
  return AppearanceObservationView(
    id: id,
    blobRef: blobRef,
    mediaType: mediaType,
    context: context,
    eventId: event.eventId,
  );
}

bool _validOpaqueBlobRef(String value) =>
    value.startsWith('blob://') &&
    value.length > 'blob://'.length &&
    value.trim() == value &&
    !value.contains(RegExp(r'\s'));

double? _double(Object? value) => value is num ? value.toDouble() : null;

int? _int(Object? value) => value is int ? value : null;

List<String> _strings(Object? value) => value is List
    ? List<String>.unmodifiable(value.whereType<String>())
    : const <String>[];

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

ObjectRef? _subjectForEvent(EventEnvelope event) {
  final types = <String>{
    if (event.eventType.startsWith('task.')) 'task',
    if (event.eventType.startsWith('review.')) 'review',
    if (event.eventType.startsWith('consent.')) 'consent',
  };
  if (types.isEmpty) return event.subjectRefs.firstOrNull;
  return event.subjectRefs.firstWhereOrNull((ref) => types.contains(ref.type));
}

extension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
