import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'application_ports.dart';
import 'strategy_loop_commands.dart';

abstract final class StrategyLoopFailureCode {
  static const invalidCommand = 'strategy_loop.invalid_command';
  static const userAuthorityRequired = 'strategy_loop.user_authority_required';
  static const agentAuthorityRequired =
      'strategy_loop.agent_authority_required';
  static const outcomeAuthorityDenied =
      'strategy_loop.outcome_authority_denied';
  static const pinnedReferenceRequired =
      'strategy_loop.pinned_reference_required';
  static const d4Forbidden = 'strategy_loop.d4_forbidden';
  static const acceptedReviewRequired = 'strategy.accepted_review_required';
  static const personalContextChanged = 'personal_context.changed';
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

final class StrategyFeedbackResult {
  StrategyFeedbackResult({
    required this.executionId,
    required this.outcomeId,
    required Iterable<String> eventIds,
  }) : eventIds = List<String>.unmodifiable(eventIds);

  final EntityId executionId;
  final EntityId outcomeId;
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

  /// Records only user-supplied context, without invoking a model.
  Future<StrategyLoopResult> recordPersonalContext(
    RecordPersonalContextCommand command,
  ) async {
    _validateUser(command);
    final fields = <String>[
      command.goal,
      command.successCriteria,
      command.currentState,
      command.constraints,
    ];
    if (command.goal.trim().isEmpty ||
        fields.any((field) => field.length > 4000)) {
      throw const StrategyLoopFailure(StrategyLoopFailureCode.invalidCommand);
    }
    final successCriteria = _parseSuccessCriteria(command.successCriteria);
    final goalId = EntityId(_ids.nextId('goal'));
    final goalRef = ObjectRef(type: 'goal', id: goalId);
    final events = <EventEnvelope>[
      _event(
        id: _ids.nextId('event'),
        type: EventTypes.goalCreated,
        command: command,
        subjects: <ObjectRef>[goalRef],
        payload: <String, Object?>{
          'expected_revision': 0,
          'title': command.goal.trim(),
          'statement': command.goal.trim(),
          'success_criteria': successCriteria,
          'source': 'user_input',
        },
      ),
      _event(
        id: _ids.nextId('event'),
        type: EventTypes.goalActivated,
        command: command,
        subjects: <ObjectRef>[goalRef],
        payload: <String, Object?>{'expected_revision': 1},
      ),
    ];
    if (command.currentState.trim().isNotEmpty) {
      events.add(_event(
        id: _ids.nextId('event'),
        type: EventTypes.personalAssetRecorded,
        command: command,
        subjects: <ObjectRef>[
          ObjectRef(type: 'personal_asset', id: EntityId(_ids.nextId('asset'))),
        ],
        sources: <ObjectRef>[goalRef],
        payload: <String, Object?>{
          'expected_revision': 0,
          'kind': 'fact',
          'title': '当前情况',
          'content': command.currentState.trim(),
          'source': 'user_input',
          'context_role': 'current_state',
          'goal_ref': goalRef.toJson(),
        },
      ));
    }
    if (command.constraints.trim().isNotEmpty) {
      events.add(_event(
        id: _ids.nextId('event'),
        type: EventTypes.constraintRecorded,
        command: command,
        subjects: <ObjectRef>[
          ObjectRef(
            type: 'constraint',
            id: EntityId(_ids.nextId('constraint')),
          ),
        ],
        sources: <ObjectRef>[goalRef],
        payload: <String, Object?>{
          'expected_revision': 0,
          'title': '执行约束',
          'content': command.constraints.trim(),
          'source': 'user_input',
          'goal_ref': goalRef.toJson(),
        },
      ));
    }
    await _eventStore.appendAll(events);
    return StrategyLoopResult(
      objectId: goalId,
      eventIds: events.map((event) => event.eventId),
    );
  }

  /// Updates current user facts while retaining earlier pinned revisions.
  Future<StrategyLoopResult> updatePersonalContext(
    UpdatePersonalContextCommand command,
  ) async {
    _validateUser(command);
    final goal = command.goal.trim(), state = command.currentState.trim();
    final successCriteria = command.successCriteria == null
        ? null
        : _parseSuccessCriteria(command.successCriteria!);
    final constraints = command.constraints?.trim();
    final stateRef = command.currentStateRef;
    if (goal.isEmpty ||
        command.goal.length > 4000 ||
        command.currentState.length > 4000 ||
        (command.successCriteria?.length ?? 0) > 4000 ||
        (command.constraints?.length ?? 0) > 4000 ||
        command.goalRef.type != 'goal' ||
        (stateRef != null && stateRef.type != 'personal_asset') ||
        (command.constraintRef != null &&
            command.constraintRef!.type != 'constraint')) {
      throw const StrategyLoopFailure(StrategyLoopFailureCode.invalidCommand);
    }
    _requirePinned(<ObjectRef>[
      command.goalRef,
      if (stateRef != null) stateRef,
      if (command.constraintRef != null) command.constraintRef!,
    ]);
    final projections = await _profileProjections(command.profileId);
    ObjectProjection owned(ObjectRef ref) {
      final value = projections['${ref.type}:${ref.id.value}'];
      if (value == null || value.revision != ref.revision) {
        throw const StrategyLoopFailure(
          StrategyLoopFailureCode.personalContextChanged,
        );
      }
      return value;
    }

    final oldGoal = owned(command.goalRef);
    if (!<String>['draft', 'active', 'paused'].contains(oldGoal.state) ||
        oldGoal.attributes['source'] != 'user_input') {
      throw const StrategyLoopFailure(StrategyLoopFailureCode.invalidCommand);
    }
    final oldState = stateRef == null ? null : owned(stateRef);
    final oldConstraint =
        command.constraintRef == null ? null : owned(command.constraintRef!);
    Object? stateGoal = oldState?.attributes['goal_ref'];
    if (oldState != null && stateGoal == null) {
      final original = await _eventStore.readBySubject(stateRef!);
      for (final event in original) {
        if (event.eventType != EventTypes.personalAssetRecorded) continue;
        final goals = event.sourceRefs.where((ref) => ref.type == 'goal');
        if (goals.isNotEmpty) stateGoal = goals.first.toJson();
      }
    }
    if (oldState != null &&
        (oldState.state != 'active' ||
            oldState.attributes['source'] != 'user_input' ||
            oldState.attributes['title'] != '当前情况' ||
            (stateGoal is Map &&
                stateGoal['id'] != command.goalRef.id.value))) {
      throw const StrategyLoopFailure(StrategyLoopFailureCode.invalidCommand);
    }
    if (oldConstraint != null) {
      final constraintGoal = oldConstraint.attributes['goal_ref'];
      if (oldConstraint.objectType != 'constraint' ||
          oldConstraint.state != 'recorded' ||
          oldConstraint.attributes['title'] != '执行约束' ||
          (oldConstraint.attributes['source'] != null &&
              oldConstraint.attributes['source'] != 'user_input') ||
          (constraintGoal is Map &&
              constraintGoal['id'] != command.goalRef.id.value)) {
        throw const StrategyLoopFailure(StrategyLoopFailureCode.invalidCommand);
      }
    }
    final events = <EventEnvelope>[];
    final previousCriteria = _parseSuccessCriteria(
      (oldGoal.attributes['success_criteria'] as List? ?? const <Object?>[])
          .whereType<String>()
          .join('\n'),
    );
    final criteriaChanged = successCriteria != null &&
        !_sameStrings(successCriteria, previousCriteria);
    final goalChanged = goal !=
            (oldGoal.attributes['title'] ?? oldGoal.attributes['statement']) ||
        criteriaChanged;
    if (goalChanged) {
      events.add(_event(
        id: _ids.nextId('event'),
        type: EventTypes.goalRevised,
        command: command,
        subjects: <ObjectRef>[command.goalRef],
        sources: <ObjectRef>[command.goalRef],
        payload: <String, Object?>{
          'expected_revision': command.goalRef.revision!.value,
          'title': goal,
          'statement': goal,
          if (criteriaChanged) 'success_criteria': successCriteria,
        },
      ));
    }
    final goalRef = ObjectRef(
      type: 'goal',
      id: command.goalRef.id,
      revision: goalChanged
          ? command.goalRef.revision!.next
          : command.goalRef.revision,
    );
    if (oldState == null && state.isNotEmpty) {
      events.add(_event(
        id: _ids.nextId('event'),
        type: EventTypes.personalAssetRecorded,
        command: command,
        subjects: <ObjectRef>[
          ObjectRef(type: 'personal_asset', id: EntityId(_ids.nextId('asset'))),
        ],
        sources: <ObjectRef>[goalRef],
        payload: <String, Object?>{
          'expected_revision': 0,
          'kind': 'fact',
          'title': '当前情况',
          'content': state,
          'source': 'user_input',
          'context_role': 'current_state',
          'goal_ref': goalRef.toJson(),
        },
      ));
    } else if (oldState != null && state != oldState.attributes['content']) {
      final oldStateRef = stateRef!;
      events.add(_event(
        id: _ids.nextId('event'),
        type: state.isEmpty
            ? EventTypes.personalAssetArchived
            : EventTypes.personalAssetRevised,
        command: command,
        subjects: <ObjectRef>[oldStateRef],
        sources: <ObjectRef>[oldStateRef, goalRef],
        payload: <String, Object?>{
          'expected_revision': oldStateRef.revision!.value,
          if (state.isNotEmpty) 'content': state,
          'context_role': 'current_state',
          'goal_ref': goalRef.toJson(),
        },
      ));
    }
    if (constraints != null) {
      final previousConstraint =
          oldConstraint?.attributes['content'] as String? ?? '';
      if (oldConstraint == null && constraints.isNotEmpty) {
        final constraintRef = ObjectRef(
          type: 'constraint',
          id: EntityId(_ids.nextId('constraint')),
        );
        events.add(_event(
          id: _ids.nextId('event'),
          type: EventTypes.constraintRecorded,
          command: command,
          subjects: <ObjectRef>[constraintRef],
          sources: <ObjectRef>[goalRef],
          payload: <String, Object?>{
            'expected_revision': 0,
            'title': '执行约束',
            'content': constraints,
            'source': 'user_input',
            'goal_ref': goalRef.toJson(),
          },
        ));
      } else if (oldConstraint != null && constraints != previousConstraint) {
        final constraintRef = command.constraintRef!;
        final archive = constraints.isEmpty;
        events.add(_event(
          id: _ids.nextId('event'),
          type: archive
              ? EventTypes.constraintArchived
              : EventTypes.constraintRevised,
          command: command,
          subjects: <ObjectRef>[constraintRef],
          sources: <ObjectRef>[constraintRef, goalRef],
          payload: <String, Object?>{
            'expected_revision': constraintRef.revision!.value,
            if (!archive) 'content': constraints,
            'goal_ref': goalRef.toJson(),
          },
        ));
      }
    }
    if (events.isNotEmpty) await _eventStore.appendAll(events);
    return StrategyLoopResult(
      objectId: command.goalRef.id,
      eventIds: events.map((event) => event.eventId),
    );
  }

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
    if (command.parentStrategy case final parent?) {
      await _requireAcceptedReview(command.profileId, parent);
    }

    final strategyId = EntityId(_ids.nextId('strategy'));
    final proposedId = _ids.nextId('event');
    final submittedId = _ids.nextId('event');
    final strategyRef = ObjectRef(type: 'strategy', id: strategyId);
    final sessionRef = ObjectRef(type: 'agent_session', id: command.sessionId);

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

  /// Completion describes execution only, never whether a plan was effective.
  Future<StrategyFeedbackResult> recordFeedback(
    RecordStrategyFeedbackCommand command,
  ) async {
    _validateUser(command);
    _requirePinned(<ObjectRef>[command.strategyRef]);
    if (command.strategyRef.type != 'strategy' ||
        command.actionId.value.trim().isEmpty ||
        command.note.length > 4000 ||
        !<ExecutionStatus>{
          ExecutionStatus.completed,
          ExecutionStatus.skipped,
          ExecutionStatus.failed,
        }.contains(command.status)) {
      throw const StrategyLoopFailure(StrategyLoopFailureCode.invalidCommand);
    }
    final projections = await _profileProjections(command.profileId);
    final strategy = projections['strategy:${command.strategyRef.id.value}'];
    final actions = strategy?.attributes['actions'];
    if (strategy == null ||
        strategy.state != 'active' ||
        strategy.revision != command.strategyRef.revision ||
        actions is! List ||
        !actions.any((action) =>
            action is Map && action['id'] == command.actionId.value)) {
      throw const StrategyLoopFailure(StrategyLoopFailureCode.invalidCommand);
    }
    final executionId = EntityId(_ids.nextId('execution'));
    final outcomeId = EntityId(_ids.nextId('outcome'));
    final executionEventId = _ids.nextId('event');
    final outcomeEventId = _ids.nextId('event');
    final executionRef = ObjectRef(
      type: 'execution',
      id: executionId,
      revision: Revision(1),
    );
    final feedback = switch (command.status) {
      ExecutionStatus.completed => '用户反馈：这一步已完成。',
      ExecutionStatus.skipped => '用户反馈：这次没有执行这一步。',
      _ => '用户反馈：这一步未完成。',
    };
    final note = command.note.trim();
    await _eventStore.appendAll(<EventEnvelope>[
      _event(
        id: executionEventId,
        type: EventTypes.executionRecorded,
        command: command,
        subjects: <ObjectRef>[ObjectRef(type: 'execution', id: executionId)],
        sources: <ObjectRef>[command.strategyRef],
        payload: <String, Object?>{
          'expected_revision': 0,
          'strategy_ref': command.strategyRef.toJson(),
          'action_id': command.actionId.value,
          'status': command.status.name,
        },
      ),
      _event(
        id: outcomeEventId,
        type: EventTypes.outcomeRecorded,
        command: command,
        subjects: <ObjectRef>[ObjectRef(type: 'outcome', id: outcomeId)],
        sources: <ObjectRef>[executionRef],
        causationId: executionEventId,
        payload: <String, Object?>{
          'expected_revision': 0,
          'execution_ref': executionRef.toJson(),
          'observation': note.isEmpty ? feedback : '$feedback 补充：$note',
          'valence': OutcomeValence.neutral.name,
          'metrics': const <String, num>{},
          'evidence_refs': const <Object?>[],
        },
      ),
    ]);
    return StrategyFeedbackResult(
      executionId: executionId,
      outcomeId: outcomeId,
      eventIds: <String>[executionEventId, outcomeEventId],
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

  Future<void> _requireAcceptedReview(
    EntityId profileId,
    ObjectRef parent,
  ) async {
    final projections = await _profileProjections(profileId);
    final accepted = projections.values.any((projection) {
      final ref = projection.attributes['strategy_ref'];
      return projection.objectType == 'review' &&
          projection.state == 'accepted' &&
          ref is Map &&
          ref['type'] == parent.type &&
          ref['id'] == parent.id.value &&
          ref['revision'] == parent.revision!.value;
    });
    if (!accepted) {
      throw const StrategyLoopFailure(
        StrategyLoopFailureCode.acceptedReviewRequired,
      );
    }
  }

  Future<Map<String, ObjectProjection>> _profileProjections(
    EntityId profileId,
  ) async {
    final events = _eventStore is CompleteProfileHistoryReader
        ? await (_eventStore as CompleteProfileHistoryReader)
            .readCompleteProfileHistory(profileId)
        : await _eventStore.readBySubject(
            ObjectRef(type: 'profile', id: profileId),
          );
    var projections = <String, ObjectProjection>{};
    var seen = <String>{};
    for (final event in events) {
      final reduction = reduceCore(
        projections: projections,
        seenEventIds: seen,
        event: event,
      );
      if (reduction.disposition != ReductionDisposition.applied) continue;
      projections = Map<String, ObjectProjection>.of(reduction.projections);
      seen = Set<String>.of(reduction.seenEventIds);
    }
    return projections;
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
      subjectRefs: <ObjectRef>[
        ...subjects,
        ObjectRef(type: 'profile', id: command.profileId),
      ],
      correlationId: command.correlationId,
      causationId: causationId,
      sourceRefs: sources,
      consentRefs: command.consentRefs,
      sensitivity: command.sensitivity,
      payload: payload,
    );
  }
}

List<String> _parseSuccessCriteria(String value) => value
    .split(RegExp(r'[\n;；]'))
    .map((criterion) => criterion.trim())
    .where((criterion) => criterion.isNotEmpty)
    .toList(growable: false);

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
