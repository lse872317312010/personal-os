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
    required Iterable<ObjectRef> sourceRefs,
    this.sensitivity = Sensitivity.d3,
    Iterable<ObjectRef> consentRefs = const <ObjectRef>[],
  })  : sourceRefs = List<ObjectRef>.unmodifiable(sourceRefs),
        consentRefs = List<ObjectRef>.unmodifiable(consentRefs);

  final ActorRef actor;
  final EntityId? profileId;
  final String correlationId;
  final List<ObjectRef> sourceRefs;
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
