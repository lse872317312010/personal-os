import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'application_ports.dart';
import 'feedback_commands.dart';

abstract final class FeedbackFailureCode {
  static const d4Forbidden = 'feedback.d4_forbidden';
  static const invalidCorrelationId = 'feedback.invalid_correlation_id';
  static const invalidExpectedRevision = 'feedback.invalid_expected_revision';
  static const executionSummaryRequired = 'feedback.execution_summary_required';
  static const skipReasonRequired = 'feedback.skip_reason_required';
  static const reviewSourcesRequired = 'feedback.review_sources_required';
  static const reviewDecisionRequiresUser =
      'feedback.review_decision_requires_user';
}

final class FeedbackUseCaseFailure implements Exception {
  const FeedbackUseCaseFailure(this.code);

  final String code;

  @override
  String toString() => 'FeedbackUseCaseFailure($code)';
}

final class CompleteTaskResult {
  const CompleteTaskResult({
    required this.executionId,
    required this.eventIds,
  });

  final String executionId;
  final List<String> eventIds;
}

final class SkipTaskResult {
  const SkipTaskResult({required this.eventId});

  final String eventId;
}

final class CreateReviewResult {
  const CreateReviewResult({required this.reviewId, required this.eventId});

  final String reviewId;
  final String eventId;
}

final class DecideReviewResult {
  const DecideReviewResult({required this.eventIds});

  final List<String> eventIds;
}

/// Writes task execution and review decisions as complete atomic event batches.
final class ActionFeedbackUseCase {
  const ActionFeedbackUseCase({
    required EventStore eventStore,
    required IdGenerator ids,
    required Clock clock,
  })  : _eventStore = eventStore,
        _ids = ids,
        _clock = clock;

  final EventStore _eventStore;
  final IdGenerator _ids;
  final Clock _clock;

  Future<CompleteTaskResult> completeTask(CompleteTaskCommand command) async {
    _validateWrite(
      command.correlationId,
      command.sensitivity,
      expectedRevision: command.expectedTaskRevision,
    );
    if (command.executionSummary.trim().isEmpty) {
      throw const FeedbackUseCaseFailure(
        FeedbackFailureCode.executionSummaryRequired,
      );
    }

    final executionId = _ids.nextId('execution');
    final executionEventId = _ids.nextId('event');
    final completionEventId = _ids.nextId('event');
    final taskRef = ObjectRef(type: 'task', id: command.taskId);
    final executionRef = ObjectRef(
      type: 'execution',
      id: EntityId(executionId),
    );
    final events = <EventEnvelope>[
      _event(
        id: executionEventId,
        type: EventTypes.executionRecorded,
        actor: command.actor,
        correlationId: command.correlationId,
        subjectRefs: <ObjectRef>[executionRef, taskRef],
        sourceRefs: <ObjectRef>[taskRef],
        consentRefs: command.consentRefs,
        sensitivity: command.sensitivity,
        payload: <String, Object?>{
          'expected_revision': 0,
          'task_ref': 'task:${command.taskId.value}',
          'actual': true,
          'summary': command.executionSummary.trim(),
        },
      ),
      _event(
        id: completionEventId,
        type: EventTypes.taskCompleted,
        actor: command.actor,
        correlationId: command.correlationId,
        causationId: executionEventId,
        subjectRefs: <ObjectRef>[taskRef],
        sourceRefs: <ObjectRef>[executionRef],
        consentRefs: command.consentRefs,
        sensitivity: command.sensitivity,
        payload: <String, Object?>{
          'expected_revision': command.expectedTaskRevision,
          'execution_ref': 'execution:$executionId',
        },
      ),
    ];
    await _eventStore.appendAll(events);
    return CompleteTaskResult(
      executionId: executionId,
      eventIds: List<String>.unmodifiable(<String>[
        executionEventId,
        completionEventId,
      ]),
    );
  }

  Future<SkipTaskResult> skipTask(SkipTaskCommand command) async {
    _validateWrite(
      command.correlationId,
      command.sensitivity,
      expectedRevision: command.expectedTaskRevision,
    );
    if (command.reason.trim().isEmpty) {
      throw const FeedbackUseCaseFailure(FeedbackFailureCode.skipReasonRequired);
    }
    final eventId = _ids.nextId('event');
    await _eventStore.appendAll(<EventEnvelope>[
      _event(
        id: eventId,
        type: EventTypes.taskSkipped,
        actor: command.actor,
        correlationId: command.correlationId,
        subjectRefs: <ObjectRef>[
          ObjectRef(type: 'task', id: command.taskId),
        ],
        consentRefs: command.consentRefs,
        sensitivity: command.sensitivity,
        payload: <String, Object?>{
          'expected_revision': command.expectedTaskRevision,
          'reason': command.reason.trim(),
        },
      ),
    ]);
    return SkipTaskResult(eventId: eventId);
  }

  Future<CreateReviewResult> createReview(CreateReviewCommand command) async {
    _validateWrite(command.correlationId, command.sensitivity);
    if (command.sourceRefs.isEmpty) {
      throw const FeedbackUseCaseFailure(
        FeedbackFailureCode.reviewSourcesRequired,
      );
    }
    final reviewId = _ids.nextId('review');
    final eventId = _ids.nextId('event');
    await _eventStore.appendAll(<EventEnvelope>[
      _event(
        id: eventId,
        type: EventTypes.reviewCreated,
        actor: command.actor,
        correlationId: command.correlationId,
        subjectRefs: <ObjectRef>[
          ObjectRef(type: 'review', id: EntityId(reviewId)),
        ],
        sourceRefs: command.sourceRefs,
        consentRefs: command.consentRefs,
        sensitivity: command.sensitivity,
        payload: const <String, Object?>{'expected_revision': 0},
      ),
    ]);
    return CreateReviewResult(reviewId: reviewId, eventId: eventId);
  }

  Future<DecideReviewResult> decideReview(DecideReviewCommand command) async {
    _validateWrite(
      command.correlationId,
      command.sensitivity,
      expectedRevision: command.expectedReviewRevision,
    );
    if (command.actor.actorType != ActorType.user) {
      throw const FeedbackUseCaseFailure(
        FeedbackFailureCode.reviewDecisionRequiresUser,
      );
    }
    final reviewedId = _ids.nextId('event');
    final decisionId = _ids.nextId('event');
    final reviewRef = ObjectRef(type: 'review', id: command.reviewId);
    final finalType = command.decision == ReviewDecision.accept
        ? EventTypes.reviewAccepted
        : EventTypes.reviewRejected;
    final events = <EventEnvelope>[
      _event(
        id: reviewedId,
        type: EventTypes.reviewUserReviewed,
        actor: command.actor,
        correlationId: command.correlationId,
        subjectRefs: <ObjectRef>[reviewRef],
        consentRefs: command.consentRefs,
        sensitivity: command.sensitivity,
        payload: <String, Object?>{
          'expected_revision': command.expectedReviewRevision,
          if (command.note?.trim().isNotEmpty ?? false)
            'note': command.note!.trim(),
        },
      ),
      _event(
        id: decisionId,
        type: finalType,
        actor: command.actor,
        correlationId: command.correlationId,
        causationId: reviewedId,
        subjectRefs: <ObjectRef>[reviewRef],
        consentRefs: command.consentRefs,
        sensitivity: command.sensitivity,
        payload: <String, Object?>{
          'expected_revision': command.expectedReviewRevision + 1,
        },
      ),
    ];
    await _eventStore.appendAll(events);
    return DecideReviewResult(
      eventIds: List<String>.unmodifiable(<String>[reviewedId, decisionId]),
    );
  }

  void _validateWrite(
    String correlationId,
    Sensitivity sensitivity, {
    int? expectedRevision,
  }) {
    if (sensitivity == Sensitivity.d4) {
      throw const FeedbackUseCaseFailure(FeedbackFailureCode.d4Forbidden);
    }
    _validateCorrelation(correlationId);
    if (expectedRevision != null && expectedRevision < 0) {
      throw const FeedbackUseCaseFailure(
        FeedbackFailureCode.invalidExpectedRevision,
      );
    }
  }

  void _validateCorrelation(String correlationId) {
    if (correlationId.trim().isEmpty) {
      throw const FeedbackUseCaseFailure(
        FeedbackFailureCode.invalidCorrelationId,
      );
    }
  }

  EventEnvelope _event({
    required String id,
    required String type,
    required ActorRef actor,
    required String correlationId,
    required List<ObjectRef> subjectRefs,
    required List<ObjectRef> consentRefs,
    required Sensitivity sensitivity,
    required Map<String, Object?> payload,
    String? causationId,
    List<ObjectRef> sourceRefs = const <ObjectRef>[],
  }) {
    final now = _clock.now().toUtc();
    return EventEnvelope(
      eventId: id,
      eventType: type,
      eventVersion: 1,
      occurredAt: now,
      recordedAt: now,
      actor: actor,
      correlationId: correlationId.trim(),
      causationId: causationId,
      subjectRefs: subjectRefs,
      sourceRefs: sourceRefs,
      consentRefs: consentRefs,
      sensitivity: sensitivity,
      payload: payload,
    );
  }
}
