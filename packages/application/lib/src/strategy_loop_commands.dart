import 'package:personal_os_domain/domain.dart';

abstract base class StrategyLoopCommand {
  StrategyLoopCommand({
    required this.actor,
    required String correlationId,
    this.sensitivity = Sensitivity.d2,
    Iterable<ObjectRef> consentRefs = const <ObjectRef>[],
  })  : correlationId = correlationId.trim(),
        consentRefs = List<ObjectRef>.unmodifiable(consentRefs);

  final ActorRef actor;
  final String correlationId;
  final Sensitivity sensitivity;
  final List<ObjectRef> consentRefs;
}

final class SubmitStrategyProposalCommand extends StrategyLoopCommand {
  SubmitStrategyProposalCommand({
    required super.actor,
    required super.correlationId,
    required this.sessionId,
    required this.title,
    required this.rationale,
    required Iterable<ObjectRef> goalRefs,
    Iterable<ObjectRef> assetRefs = const <ObjectRef>[],
    required Iterable<Map<String, Object?>> actions,
    Iterable<String> assumptions = const <String>[],
    this.parentStrategy,
    super.sensitivity,
    super.consentRefs,
  })  : goalRefs = List<ObjectRef>.unmodifiable(goalRefs),
        assetRefs = List<ObjectRef>.unmodifiable(assetRefs),
        actions = List<Map<String, Object?>>.unmodifiable(
          actions.map(Map<String, Object?>.unmodifiable),
        ),
        assumptions = List<String>.unmodifiable(assumptions);

  final EntityId sessionId;
  final String title;
  final String rationale;
  final List<ObjectRef> goalRefs;
  final List<ObjectRef> assetRefs;
  final List<Map<String, Object?>> actions;
  final List<String> assumptions;
  final ObjectRef? parentStrategy;
}

enum ProposalDecision { accept, reject }

final class DecideStrategyProposalCommand extends StrategyLoopCommand {
  DecideStrategyProposalCommand({
    required super.actor,
    required super.correlationId,
    required this.strategyId,
    required this.expectedRevision,
    required this.decision,
    this.note,
    super.sensitivity,
    super.consentRefs,
  });

  final EntityId strategyId;
  final int expectedRevision;
  final ProposalDecision decision;
  final String? note;
}

final class ActivateStrategyCommand extends StrategyLoopCommand {
  ActivateStrategyCommand({
    required super.actor,
    required super.correlationId,
    required this.strategyId,
    required this.expectedRevision,
    super.sensitivity,
    super.consentRefs,
  });

  final EntityId strategyId;
  final int expectedRevision;
}

final class RecordStrategyExecutionCommand extends StrategyLoopCommand {
  RecordStrategyExecutionCommand({
    required super.actor,
    required super.correlationId,
    required this.strategyRef,
    required this.actionId,
    required this.status,
    this.note,
    super.sensitivity,
    super.consentRefs,
  });

  final ObjectRef strategyRef;
  final EntityId actionId;
  final ExecutionStatus status;
  final String? note;
}

final class RecordStrategyOutcomeCommand extends StrategyLoopCommand {
  RecordStrategyOutcomeCommand({
    required super.actor,
    required super.correlationId,
    required this.executionRef,
    required this.observation,
    required this.valence,
    Map<String, num> metrics = const <String, num>{},
    Iterable<ObjectRef> evidenceRefs = const <ObjectRef>[],
    super.sensitivity,
    super.consentRefs,
  })  : metrics = Map<String, num>.unmodifiable(metrics),
        evidenceRefs = List<ObjectRef>.unmodifiable(evidenceRefs);

  final ObjectRef executionRef;
  final String observation;
  final OutcomeValence valence;
  final Map<String, num> metrics;
  final List<ObjectRef> evidenceRefs;
}
