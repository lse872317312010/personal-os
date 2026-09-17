import 'identity.dart';

enum PersonalAssetKind {
  fact,
  preference,
  constraint,
  capability,
  resource,
  relationship,
  observation,
}

enum RecordStatus { active, superseded, archived }

enum StrategyStatus { proposed, accepted, active, completed, abandoned }

enum ExecutionStatus { planned, started, completed, skipped, failed }

enum OutcomeValence { positive, neutral, negative, mixed }

enum AgentSessionStatus { opened, proposalSubmitted, closed, failed }

/// A user-owned piece of durable context. It records evidence, not inference.
final class PersonalAsset {
  PersonalAsset({
    required this.id,
    required this.revision,
    required this.kind,
    required String title,
    required String content,
    required this.recordedAt,
    this.status = RecordStatus.active,
    this.source,
    this.sensitivity = 'private',
    this.tags = const <String>[],
  })  : title = _nonBlank(title, 'PersonalAsset.title'),
        content = _nonBlank(content, 'PersonalAsset.content');

  final EntityId id;
  final Revision revision;
  final PersonalAssetKind kind;
  final String title;
  final String content;
  final DateTime recordedAt;
  final RecordStatus status;
  final String? source;
  final String sensitivity;
  final List<String> tags;

  ObjectRef get ref => ObjectRef(
        type: 'personal_asset',
        id: id,
        revision: revision,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'revision': revision.value,
        'kind': kind.name,
        'title': title,
        'content': content,
        'recorded_at': recordedAt.toUtc().toIso8601String(),
        'status': status.name,
        if (source != null) 'source': source,
        'sensitivity': sensitivity,
        'tags': tags,
      };
}

/// A versioned objective owned by the user.
final class Goal {
  Goal({
    required this.id,
    required this.revision,
    required String statement,
    required this.createdAt,
    this.successCriteria = const <String>[],
    this.status = RecordStatus.active,
    this.targetAt,
  }) : statement = _nonBlank(statement, 'Goal.statement');

  final EntityId id;
  final Revision revision;
  final String statement;
  final List<String> successCriteria;
  final DateTime createdAt;
  final DateTime? targetAt;
  final RecordStatus status;

  ObjectRef get ref => ObjectRef(type: 'goal', id: id, revision: revision);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'revision': revision.value,
        'statement': statement,
        'success_criteria': successCriteria,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (targetAt != null) 'target_at': targetAt!.toUtc().toIso8601String(),
        'status': status.name,
      };
}

/// A concrete, versioned plan proposed by an external reasoning agent.
final class Strategy {
  Strategy({
    required this.id,
    required this.revision,
    required String title,
    required String rationale,
    required this.createdAt,
    required this.createdBySession,
    this.goalRefs = const <ObjectRef>[],
    this.assetRefs = const <ObjectRef>[],
    this.actions = const <StrategyAction>[],
    this.assumptions = const <String>[],
    this.status = StrategyStatus.proposed,
    this.parentStrategy,
  })  : title = _nonBlank(title, 'Strategy.title'),
        rationale = _nonBlank(rationale, 'Strategy.rationale');

  final EntityId id;
  final Revision revision;
  final String title;
  final String rationale;
  final DateTime createdAt;
  final EntityId createdBySession;
  final List<ObjectRef> goalRefs;
  final List<ObjectRef> assetRefs;
  final List<StrategyAction> actions;
  final List<String> assumptions;
  final StrategyStatus status;
  final ObjectRef? parentStrategy;

  ObjectRef get ref => ObjectRef(type: 'strategy', id: id, revision: revision);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'revision': revision.value,
        'title': title,
        'rationale': rationale,
        'created_at': createdAt.toUtc().toIso8601String(),
        'created_by_session': createdBySession.value,
        'goal_refs': goalRefs.map((item) => item.toJson()).toList(),
        'asset_refs': assetRefs.map((item) => item.toJson()).toList(),
        'actions': actions.map((item) => item.toJson()).toList(),
        'assumptions': assumptions,
        'status': status.name,
        if (parentStrategy != null) 'parent_strategy': parentStrategy!.toJson(),
      };
}

final class StrategyAction {
  StrategyAction({
    required this.id,
    required String instruction,
    this.successMeasure,
    this.dueAt,
  }) : instruction = _nonBlank(instruction, 'StrategyAction.instruction');

  final EntityId id;
  final String instruction;
  final String? successMeasure;
  final DateTime? dueAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'instruction': instruction,
        if (successMeasure != null) 'success_measure': successMeasure,
        if (dueAt != null) 'due_at': dueAt!.toUtc().toIso8601String(),
      };
}

/// What the user actually did. It is separate from an agent recommendation.
final class Execution {
  Execution({
    required this.id,
    required this.strategyRef,
    required this.actionId,
    required this.status,
    required this.recordedAt,
    this.note,
  });

  final EntityId id;
  final ObjectRef strategyRef;
  final EntityId actionId;
  final ExecutionStatus status;
  final DateTime recordedAt;
  final String? note;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'strategy_ref': strategyRef.toJson(),
        'action_id': actionId.value,
        'status': status.name,
        'recorded_at': recordedAt.toUtc().toIso8601String(),
        if (note != null) 'note': note,
      };
}

/// A deterministic result or user observation linked to an execution.
final class Outcome {
  Outcome({
    required this.id,
    required this.executionRef,
    required String observation,
    required this.observedAt,
    required this.valence,
    this.metrics = const <String, num>{},
    this.evidenceRefs = const <ObjectRef>[],
  }) : observation = _nonBlank(observation, 'Outcome.observation');

  final EntityId id;
  final ObjectRef executionRef;
  final String observation;
  final DateTime observedAt;
  final OutcomeValence valence;
  final Map<String, num> metrics;
  final List<ObjectRef> evidenceRefs;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'execution_ref': executionRef.toJson(),
        'observation': observation,
        'observed_at': observedAt.toUtc().toIso8601String(),
        'valence': valence.name,
        'metrics': metrics,
        'evidence_refs': evidenceRefs.map((item) => item.toJson()).toList(),
      };
}

/// A comparison that explains why a strategy should be retained or changed.
final class Review {
  Review({
    required this.id,
    required this.strategyRef,
    required String summary,
    required this.reviewedAt,
    required this.reviewedBySession,
    this.outcomeRefs = const <ObjectRef>[],
    this.keep = const <String>[],
    this.change = const <String>[],
  }) : summary = _nonBlank(summary, 'Review.summary');

  final EntityId id;
  final ObjectRef strategyRef;
  final String summary;
  final DateTime reviewedAt;
  final EntityId reviewedBySession;
  final List<ObjectRef> outcomeRefs;
  final List<String> keep;
  final List<String> change;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'strategy_ref': strategyRef.toJson(),
        'summary': summary,
        'reviewed_at': reviewedAt.toUtc().toIso8601String(),
        'reviewed_by_session': reviewedBySession.value,
        'outcome_refs': outcomeRefs.map((item) => item.toJson()).toList(),
        'keep': keep,
        'change': change,
      };
}

/// Audit record for one external Agent/Harness interaction.
final class AgentSession {
  AgentSession({
    required this.id,
    required String agentId,
    required String protocolVersion,
    required this.openedAt,
    this.status = AgentSessionStatus.opened,
    this.closedAt,
    this.contextRefs = const <ObjectRef>[],
    this.proposalRefs = const <ObjectRef>[],
  })  : agentId = _nonBlank(agentId, 'AgentSession.agentId'),
        protocolVersion =
            _nonBlank(protocolVersion, 'AgentSession.protocolVersion');

  final EntityId id;
  final String agentId;
  final String protocolVersion;
  final DateTime openedAt;
  final DateTime? closedAt;
  final AgentSessionStatus status;
  final List<ObjectRef> contextRefs;
  final List<ObjectRef> proposalRefs;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.value,
        'agent_id': agentId,
        'protocol_version': protocolVersion,
        'opened_at': openedAt.toUtc().toIso8601String(),
        if (closedAt != null) 'closed_at': closedAt!.toUtc().toIso8601String(),
        'status': status.name,
        'context_refs': contextRefs.map((item) => item.toJson()).toList(),
        'proposal_refs': proposalRefs.map((item) => item.toJson()).toList(),
      };
}

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}
