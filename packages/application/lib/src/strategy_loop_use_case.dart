import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'application_ports.dart';
import 'strategy_loop_commands.dart';

abstract final class StrategyLoopFailureCode {
  static const invalidCommand = 'strategy_loop.invalid_command';
  static const userAuthorityRequired = 'strategy_loop.user_authority_required';
  static const agentAuthorityRequired = 'strategy_loop.agent_authority_required';
  static const outcomeAuthorityDenied = 'strategy_loop.outcome_authority_denied';
  static const pinnedReferenceRequired =
      'strategy_loop.pinned_reference_required';
  static const d4Forbidden = 'strategy_loop.d4_forbidden';
}

final class StrategyLoopFailure implements Exception {
  const StrategyLoopFailure(this.code);
  final String code;

  @override
  String toString() => 'StrategyLoopFailure($code)';
}

final class StrategyLoopResult {
  StrategyLoopResult({
    required this.objectId,
    required Iterable<String> eventIds,
  }) : eventIds = List<String>.unmodifiable(eventIds);

  final EntityId objectId;
  final List<String> eventIds;
}

/// Application authority boundary for the external-Agent strategy loop.
final class StrategyLoopUseCase {
  const StrategyLoopUseCase({
    required EventStore eventStore,
    required IdGenerator ids,
    required Clock clock,
  })  : _eventStore = eventStore,
        _ids = ids,
        _clock = clock;

  final EventStore _eventStore;
  final IdGenerator _ids;
  final Clock _clock;

  Future<StrategyLoopResult> submitProposal(
    SubmitStrategyProposalCommand command,
  ) async {
    _validateCommon(command);
    if (command.actor.actorType != ActorType.agent) {
      throw const StrategyLoopFailure(
        StrategyLoopFailureCode.agentAuthorityRequired,
      );
    }
    if (command.expectedSessionRevision < 0 ||
        command.title.trim().isEmpty ||
        command.rationale.trim().isEmpty ||
        command.goalRefs.isEmpty ||
        command.actions.isEmpty) {
      throw const StrategyLoopFailure(StrategyLoopFailureCode.invalidCommand);
    }
    _requirePinned(<ObjectRef>[
      ...command.goalRefs,
      ...command.assetRefs,
      if (command.parentStrategy != null) command.parentStrategy!,
    ]);

    final strategyId = EntityId(_ids.nextId('strategy'));
    final proposedId = _ids.nextId('event');
    final submittedId = _ids.nextId('event');
    final strategyRef = ObjectRef(type: 'strategy', id: strategyId);
    final sessionRef =
        ObjectRef(type: 'agent_session', id: command.sessionId);

    await _eventStore.appendAll(<EventEnvelope>[
      _event(
        id: proposedId,
        type: EventTypes.strategyProposed,
        command: command,
        subjects: <ObjectRef>[strategyRef],
        sources: <ObjectRef>[
          sessionRef,
          ...command.goalRefs,
          ...command.assetRefs,
          if (command.parentStrategy != null) command.parentStrategy!,
        ],
        payload: <String, Object?>{
          'expected_revision': 0,
          'title': command.title.trim(),
          'rationale': command.rationale.trim(),
          'created_by_session': command.sessionId.value,
          'goal_refs': command.goalRefs.map((ref) => ref.toJson()).toList(),
          'asset_refs': command.assetRefs.map((ref) => ref.toJson()).toList(),
          'actions': command.actions,
          'assumptions': command.assumptions,
          if (command.parentStrategy != null)
            'parent_strategy': command.parentStrategy!.toJson(),
        },
      ),
      _event(
        id: submittedId,
        type: EventTypes.agentSessionProposalSubmitted,
        command: command,
        subjects: <ObjectRef>[sessionRef],
        sources: <ObjectRef>[strategyRef],
        causationId: proposedId,
        payload: <String, Object?>{
          'expected_revision': command.expectedSessionRevision,
          'proposal_ref': strategyRef.toJson(),
        },
      ),
    ]);
    return StrategyLoopResult(
      objectId: strategyId,
      eventIds: <String>[proposedId, submittedId],
    );
  }

  Future<StrategyLoopResult> decideProposal(
    DecideStrategyProposalCommand command,
  ) async {
    _validateUser(command, command.expectedRevision);
    final eventId = _ids.nextId('event');
    final type = command.decision == ProposalDecision.accept
        ? EventTypes.strategyAccepted
        : EventTypes.strategyAbandoned;
    await _eventStore.appendAll(<EventEnvelope>[
      _event(
        id: eventId,
        type: type,
        command: command,
        subjects: <ObjectRef>[
          ObjectRef(type: 'strategy', id: command.strategyId),
        ],
        payload: <String, Object?>{
          'expected_revision': command.expectedRevision,
          'decision': command.decision.name,
          if (command.note?.trim().isNotEmpty ?? false)
            'note': command.note!.trim(),
        },
      ),
    ]);
    return StrategyLoopResult(
      objectId: command.strategyId,
      eventIds: <String>[eventId],
    );
  }

  Future<StrategyLoopResult> activateStrategy(
    ActivateStrategyCommand command,
  ) async {
    _validateUser(command, command.expectedRevision);
    final eventId = _ids.nextId('event');
    await _eventStore.appendAll(<EventEnvelope>[
      _event(
        id: eventId,
        type: EventTypes.strategyActivated,
        command: command,
        subjects: <ObjectRef>[
          ObjectRef(type: 'strategy', id: command.strategyId),
        ],
        payload: <String, Object?>{
          'expected_revision': command.expectedRevision,
        },
      ),
    ]);
    return StrategyLoopResult(
      objectId: command.strategyId,
      eventIds: <String>[eventId],
    );
  }

  Future<StrategyLoopResult> recordExecution(
    RecordStrategyExecutionCommand command,
  ) async {
    _validateUser(command);
    _requirePinned(<ObjectRef>[command.strategyRef]);
    final executionId = EntityId(_ids.nextId('execution'));
    final eventId = _ids.nextId('event');
    await _eventStore.appendAll(<EventEnvelope>[
      _event(
        id: eventId,
        type: EventTypes.executionRecorded,
        command: command,
        subjects: <ObjectRef>[
          ObjectRef(type: 'execution', id: executionId),
        ],
        sources: <ObjectRef>[command.strategyRef],
        payload: <String, Object?>{
          'expected_revision': 0,
          'strategy_ref': command.strategyRef.toJson(),
          'action_id': command.actionId.value,
          'status': command.status.name,
          if (command.note?.trim().isNotEmpty ?? false)
            'note': command.note!.trim(),
        },
      ),
    ]);
    return StrategyLoopResult(
      objectId: executionId,
      eventIds: <String>[eventId],
    );
  }

  Future<StrategyLoopResult> recordOutcome(
    RecordStrategyOutcomeCommand command,
  ) async {
    _validateCommon(command);
    if (command.actor.actorType != ActorType.user &&
        command.actor.actorType != ActorType.connector) {
      throw const StrategyLoopFailure(
        StrategyLoopFailureCode.outcomeAuthorityDenied,
      );
    }
    _requirePinned(<ObjectRef>[command.executionRef]);
    if (command.observation.trim().isEmpty) {
      throw const StrategyLoopFailure(StrategyLoopFailureCode.invalidCommand);
    }
    final outcomeId = EntityId(_ids.nextId('outcome'));
    final eventId = _ids.nextId('event');
    await _eventStore.appendAll(<EventEnvelope>[
      _event(
        id: eventId,
        type: EventTypes.outcomeRecorded,
        command: command,
        subjects: <ObjectRef>[
          ObjectRef(type: 'outcome', id: outcomeId),
        ],
        sources: <ObjectRef>[
          command.executionRef,
          ...command.evidenceRefs,
        ],
        payload: <String, Object?>{
          'expected_revision': 0,
          'execution_ref': command.executionRef.toJson(),
          'observation': command.observation.trim(),
          'valence': command.valence.name,
          'metrics': command.metrics,
          'evidence_refs':
              command.evidenceRefs.map((ref) => ref.toJson()).toList(),
        },
      ),
    ]);
    return StrategyLoopResult(
      objectId: outcomeId,
      eventIds: <String>[eventId],
    );
  }

  void _validateUser(StrategyLoopCommand command, [int? revision]) {
    _validateCommon(command);
    if (command.actor.actorType != ActorType.user) {
      throw const StrategyLoopFailure(
        StrategyLoopFailureCode.userAuthorityRequired,
      );
    }
    if (revision != null && revision < 0) {
      throw const StrategyLoopFailure(StrategyLoopFailureCode.invalidCommand);
    }
  }

  void _validateCommon(StrategyLoopCommand command) {
    if (command.correlationId.isEmpty) {
      throw const StrategyLoopFailure(StrategyLoopFailureCode.invalidCommand);
    }
    if (command.sensitivity == Sensitivity.d4) {
      throw const StrategyLoopFailure(StrategyLoopFailureCode.d4Forbidden);
    }
  }

  void _requirePinned(Iterable<ObjectRef> refs) {
    if (refs.any((ref) => ref.revision == null)) {
      throw const StrategyLoopFailure(
        StrategyLoopFailureCode.pinnedReferenceRequired,
      );
    }
  }

  EventEnvelope _event({
    required String id,
    required String type,
    required StrategyLoopCommand command,
    required List<ObjectRef> subjects,
    required Map<String, Object?> payload,
    List<ObjectRef> sources = const <ObjectRef>[],
    String? causationId,
  }) {
    final now = _clock.now().toUtc();
    return EventEnvelope(
      eventId: id,
      eventType: type,
      eventVersion: 1,
      occurredAt: now,
      recordedAt: now,
      actor: command.actor,
      subjectRefs: subjects,
      correlationId: command.correlationId,
      causationId: causationId,
      sourceRefs: sources,
      consentRefs: command.consentRefs,
      sensitivity: command.sensitivity,
      payload: payload,
    );
  }
}
