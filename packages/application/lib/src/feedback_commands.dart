import 'package:personal_os_domain/domain.dart';

final class CompleteTaskCommand {
  CompleteTaskCommand({
    required this.taskId,
    this.profileId,
    required this.expectedTaskRevision,
    required this.actor,
    required this.correlationId,
    required this.executionSummary,
    this.sensitivity = Sensitivity.d2,
    Iterable<ObjectRef> consentRefs = const <ObjectRef>[],
  }) : consentRefs = List<ObjectRef>.unmodifiable(consentRefs);

  final EntityId taskId;

  /// Optional profile linkage for event-stream reconstruction.
  ///
  /// Omitting it preserves the legacy task-only event shape.
  final EntityId? profileId;
  final int expectedTaskRevision;
  final ActorRef actor;
  final String correlationId;
  final String executionSummary;
  final Sensitivity sensitivity;
  final List<ObjectRef> consentRefs;
}

final class SkipTaskCommand {
  SkipTaskCommand({
    required this.taskId,
    this.profileId,
    required this.expectedTaskRevision,
    required this.actor,
    required this.correlationId,
    required this.reason,
    this.sensitivity = Sensitivity.d2,
    Iterable<ObjectRef> consentRefs = const <ObjectRef>[],
  }) : consentRefs = List<ObjectRef>.unmodifiable(consentRefs);

  final EntityId taskId;
  final EntityId? profileId;
  final int expectedTaskRevision;
  final ActorRef actor;
  final String correlationId;
  final String reason;
  final Sensitivity sensitivity;
  final List<ObjectRef> consentRefs;
}

final class CreateReviewCommand {
  CreateReviewCommand({
    this.profileId,
    required this.actor,
    required this.correlationId,
    Iterable<ObjectRef> sourceRefs = const <ObjectRef>[],
    this.strategyRef,
    this.reviewedBySession,
    this.summary,
    this.conclusion,
    Iterable<ObjectRef> executionRefs = const <ObjectRef>[],
    Iterable<ObjectRef> outcomeRefs = const <ObjectRef>[],
    Iterable<ObjectRef> feedbackRefs = const <ObjectRef>[],
    Iterable<String> keep = const <String>[],
    Iterable<String> change = const <String>[],
    Iterable<String> unknowns = const <String>[],
    this.sensitivity = Sensitivity.d3,
    Iterable<ObjectRef> consentRefs = const <ObjectRef>[],
  })  : sourceRefs = List<ObjectRef>.unmodifiable(sourceRefs),
        executionRefs = List<ObjectRef>.unmodifiable(executionRefs),
        outcomeRefs = List<ObjectRef>.unmodifiable(outcomeRefs),
        feedbackRefs = List<ObjectRef>.unmodifiable(feedbackRefs),
        keep = List<String>.unmodifiable(keep),
        change = List<String>.unmodifiable(change),
        unknowns = List<String>.unmodifiable(unknowns),
        consentRefs = List<ObjectRef>.unmodifiable(consentRefs);

  final ActorRef actor;
  final EntityId? profileId;
  final String correlationId;
  final List<ObjectRef> sourceRefs;
  final ObjectRef? strategyRef;
  final EntityId? reviewedBySession;
  final String? summary;
  final StrategyReviewConclusion? conclusion;
  final List<ObjectRef> executionRefs;
  final List<ObjectRef> outcomeRefs;
  final List<ObjectRef> feedbackRefs;
  final List<String> keep;
  final List<String> change;
  final List<String> unknowns;
  final Sensitivity sensitivity;
  final List<ObjectRef> consentRefs;
}

enum ReviewDecision { accept, reject }

final class DecideReviewCommand {
  DecideReviewCommand({
    required this.reviewId,
    this.profileId,
    required this.expectedReviewRevision,
    required this.actor,
    required this.correlationId,
    required this.decision,
    this.note,
    this.sensitivity = Sensitivity.d3,
    Iterable<ObjectRef> consentRefs = const <ObjectRef>[],
  }) : consentRefs = List<ObjectRef>.unmodifiable(consentRefs);

  final EntityId reviewId;
  final EntityId? profileId;
  final int expectedReviewRevision;
  final ActorRef actor;
  final String correlationId;
  final ReviewDecision decision;
  final String? note;
  final Sensitivity sensitivity;
  final List<ObjectRef> consentRefs;
}
