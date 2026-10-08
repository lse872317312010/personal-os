import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  late _Store store;
  late StrategyLoopUseCase useCase;
  final goalRef = ObjectRef(
    type: 'goal',
    id: EntityId('goal-1'),
    revision: Revision(2),
  );
  final agent = ActorRef(
    actorId: 'harness.codex',
    actorType: ActorType.agent,
    authoritySource: 'mcp',
    sessionOrRunId: 'session-1',
    onBehalfOf: 'user',
  );
  final user = ActorRef(
    actorId: 'user',
    actorType: ActorType.user,
    authoritySource: 'android',
  );

  setUp(() {
    store = _Store();
    useCase = StrategyLoopUseCase(
      eventStore: store,
      ids: _Ids(),
      clock: _Clock(),
    );
  });

  test('personal context is recorded atomically as user-owned objects',
      () async {
    final result = await useCase.recordPersonalContext(
      RecordPersonalContextCommand(
        actor: user,
        profileId: EntityId('primary-user'),
        correlationId: 'context-1',
        goal: ' Learn consistently ',
        successCriteria: 'Three sessions in one week',
        currentState: 'Thirty minutes available in the evening',
        constraints: 'Spend no money',
      ),
    );
    expect(store.batches, hasLength(1));
    expect(result.eventIds, hasLength(4));
    expect(store.batches.single.map((event) => event.eventType), <String>[
      EventTypes.goalCreated,
      EventTypes.goalActivated,
      EventTypes.personalAssetRecorded,
      EventTypes.constraintRecorded,
    ]);
    expect(store.batches.single.first.payload['title'], 'Learn consistently');
    expect(
      store.batches.single
          .every((event) => event.actor.actorType == ActorType.user),
      isTrue,
    );
  });

  test('an agent cannot write user facts through context setup', () async {
    await expectLater(
      useCase.recordPersonalContext(
        RecordPersonalContextCommand(
          actor: agent,
          profileId: EntityId('primary-user'),
          correlationId: 'context-1',
          goal: 'Invent a goal',
        ),
      ),
      throwsA(isA<StrategyLoopFailure>().having(
        (error) => error.code,
        'code',
        StrategyLoopFailureCode.userAuthorityRequired,
      )),
    );
    expect(store.batches, isEmpty);
  });

  test('context edits retain identities, prior evidence and hidden criteria',
      () async {
    final created = await useCase.recordPersonalContext(
      RecordPersonalContextCommand(
        actor: user,
        profileId: EntityId('primary-user'),
        correlationId: 'create',
        goal: 'Study twenty minutes',
        currentState: 'Tired after work',
        successCriteria: 'Three sessions',
        constraints: 'No spending',
      ),
    );
    final original = store.batches.single.toList();
    final asset = original[2].subjectRefs.first;
    final edited = await useCase.updatePersonalContext(
      UpdatePersonalContextCommand(
        actor: user,
        profileId: EntityId('primary-user'),
        correlationId: 'edit',
        goalRef: ObjectRef(
            type: 'goal', id: created.objectId, revision: Revision(2)),
        currentStateRef:
            ObjectRef(type: asset.type, id: asset.id, revision: Revision(1)),
        goal: 'Study ten minutes',
        currentState: 'Free on weekends',
      ),
    );
    expect(edited.objectId, created.objectId);
    expect(edited.eventIds, hasLength(2));
    expect(store.batches.first, original);
    final projections = _project(store);
    final goal = projections['goal:${created.objectId.value}']!;
    expect(goal.revision.value, 3);
    expect(goal.state, 'active');
    expect(goal.attributes['title'], 'Study ten minutes');
    expect(goal.attributes['success_criteria'], <String>['Three sessions']);
    expect(projections['personal_asset:${asset.id.value}']!.revision.value, 2);
    expect(
        projections['personal_asset:${asset.id.value}']!.attributes['content'],
        'Free on weekends');
    expect(
        projections.values.where((p) => p.objectType == 'goal'), hasLength(1));
    expect(projections.values.where((p) => p.objectType == 'constraint'),
        hasLength(1));
  });

  test('success criteria and execution constraints revise and archive cleanly',
      () async {
    final created = await useCase.recordPersonalContext(
      RecordPersonalContextCommand(
        actor: user,
        profileId: EntityId('primary-user'),
        correlationId: 'create',
        goal: 'Study consistently',
        successCriteria: 'Three sessions\nOne reflection',
        constraints: 'No spending',
      ),
    );
    final constraint = store.batches.single
        .singleWhere(
            (event) => event.eventType == EventTypes.constraintRecorded)
        .subjectRefs
        .first;
    final edited = await useCase.updatePersonalContext(
      UpdatePersonalContextCommand(
        actor: user,
        profileId: EntityId('primary-user'),
        correlationId: 'edit',
        goalRef: ObjectRef(
            type: 'goal', id: created.objectId, revision: Revision(2)),
        constraintRef: ObjectRef(
            type: constraint.type, id: constraint.id, revision: Revision(1)),
        goal: 'Study consistently',
        successCriteria: 'Four sessions',
        currentState: '',
        constraints: 'Only use free resources',
      ),
    );
    expect(edited.eventIds, hasLength(2));
    expect(store.batches.last.map((event) => event.eventType), <String>[
      EventTypes.goalRevised,
      EventTypes.constraintRevised,
    ]);
    var projections = _project(store);
    expect(
        projections['goal:${created.objectId.value}']!
            .attributes['success_criteria'],
        <String>['Four sessions']);
    var savedConstraint = projections['constraint:${constraint.id.value}']!;
    expect(savedConstraint.revision.value, 2);
    expect(savedConstraint.attributes['content'], 'Only use free resources');

    await useCase.updatePersonalContext(
      UpdatePersonalContextCommand(
        actor: user,
        profileId: EntityId('primary-user'),
        correlationId: 'archive-constraint',
        goalRef: ObjectRef(
            type: 'goal', id: created.objectId, revision: Revision(3)),
        constraintRef: ObjectRef(
            type: constraint.type, id: constraint.id, revision: Revision(2)),
        goal: 'Study consistently',
        successCriteria: 'Four sessions',
        currentState: '',
        constraints: '',
      ),
    );
    expect(store.batches.last.single.eventType, EventTypes.constraintArchived);
    projections = _project(store);
    savedConstraint = projections['constraint:${constraint.id.value}']!;
    expect(savedConstraint.state, 'archived');
    expect(savedConstraint.revision.value, 3);
    expect(savedConstraint.attributes['content'], 'Only use free resources');
  });

  test('legacy constraint ownership comes from its recorded source goal',
      () async {
    final firstGoal = await useCase.recordPersonalContext(
      RecordPersonalContextCommand(
        actor: user,
        profileId: EntityId('primary-user'),
        correlationId: 'first-goal',
        goal: 'First goal',
      ),
    );
    final secondGoal = await useCase.recordPersonalContext(
      RecordPersonalContextCommand(
        actor: user,
        profileId: EntityId('primary-user'),
        correlationId: 'second-goal',
        goal: 'Second goal',
      ),
    );
    final constraintRef = ObjectRef(
      type: 'constraint',
      id: EntityId('legacy-constraint'),
    );
    await store.appendAll(<EventEnvelope>[
      EventEnvelope(
        eventId: 'legacy-constraint-recorded',
        eventType: EventTypes.constraintRecorded,
        eventVersion: 1,
        occurredAt: DateTime.utc(2026, 10, 4),
        recordedAt: DateTime.utc(2026, 10, 4),
        actor: user,
        subjectRefs: <ObjectRef>[
          constraintRef,
          ObjectRef(type: 'profile', id: EntityId('primary-user')),
        ],
        correlationId: 'legacy-constraint',
        sourceRefs: <ObjectRef>[
          ObjectRef(
            type: 'goal',
            id: firstGoal.objectId,
            revision: Revision(2),
          ),
        ],
        sensitivity: Sensitivity.d1,
        payload: <String, Object?>{
          'expected_revision': 0,
          'title': '执行约束',
          'content': 'Keep the original restriction',
          'source': 'user_input',
        },
      ),
    ]);

    await expectLater(
      useCase.updatePersonalContext(
        UpdatePersonalContextCommand(
          actor: user,
          profileId: EntityId('primary-user'),
          correlationId: 'reassign-legacy-constraint',
          goalRef: ObjectRef(
            type: 'goal',
            id: secondGoal.objectId,
            revision: Revision(2),
          ),
          constraintRef: ObjectRef(
            type: constraintRef.type,
            id: constraintRef.id,
            revision: Revision(1),
          ),
          goal: 'Second goal',
          currentState: '',
          constraints: 'Reassigned restriction',
        ),
      ),
      throwsA(isA<StrategyLoopFailure>().having(
        (error) => error.code,
        'code',
        StrategyLoopFailureCode.invalidCommand,
      )),
    );
    expect(store.batches, hasLength(3));
    expect(
        _project(store)['constraint:${constraintRef.id.value}']!
            .attributes['content'],
        'Keep the original restriction');
  });

  test(
      'unchanged, stale, foreign and agent context edits never partially write',
      () async {
    final created = await useCase.recordPersonalContext(
      RecordPersonalContextCommand(
          actor: user,
          profileId: EntityId('primary-user'),
          correlationId: 'create',
          goal: 'Study',
          currentState: 'Ten minutes'),
    );
    final asset = store.batches.single[2].subjectRefs.first;
    UpdatePersonalContextCommand edit({
      ActorRef? actor,
      String profile = 'primary-user',
      int? goalRevision = 2,
      int stateRevision = 1,
      String goal = 'Study',
      String state = 'Ten minutes',
    }) =>
        UpdatePersonalContextCommand(
          actor: actor ?? user,
          profileId: EntityId(profile),
          correlationId: 'edit',
          goalRef: ObjectRef(
              type: 'goal',
              id: created.objectId,
              revision: goalRevision == null ? null : Revision(goalRevision)),
          currentStateRef: ObjectRef(
              type: asset.type,
              id: asset.id,
              revision: Revision(stateRevision)),
          goal: goal,
          currentState: state,
        );
    expect((await useCase.updatePersonalContext(edit())).eventIds, isEmpty);
    expect(store.batches, hasLength(1));
    for (final command in <UpdatePersonalContextCommand>[
      edit(actor: agent),
      edit(profile: 'someone-else'),
      edit(goalRevision: null),
      edit(goalRevision: 1),
      edit(stateRevision: 0, goal: 'Must not partially change'),
    ]) {
      await expectLater(useCase.updatePersonalContext(command),
          throwsA(isA<StrategyLoopFailure>()));
    }
    expect(store.batches, hasLength(1));
    await useCase.updatePersonalContext(edit(state: 'Weekends'));
    await expectLater(
        useCase.updatePersonalContext(edit(goal: 'Stale edit')),
        throwsA(isA<StrategyLoopFailure>().having((e) => e.code, 'code',
            StrategyLoopFailureCode.personalContextChanged)));
    expect(store.batches, hasLength(2));
    expect(
        _project(store)['goal:${created.objectId.value}']!.revision.value, 2);
  });

  test('clearing optional context archives its evidence without blank facts',
      () async {
    final created = await useCase.recordPersonalContext(
      RecordPersonalContextCommand(
          actor: user,
          profileId: EntityId('primary-user'),
          correlationId: 'create',
          goal: 'Study',
          currentState: 'Ten minutes'),
    );
    final asset = store.batches.single[2].subjectRefs.first;
    final ref =
        ObjectRef(type: 'goal', id: created.objectId, revision: Revision(2));
    await useCase.updatePersonalContext(UpdatePersonalContextCommand(
      actor: user,
      profileId: EntityId('primary-user'),
      correlationId: 'clear',
      goalRef: ref,
      goal: 'Study',
      currentState: '',
      currentStateRef:
          ObjectRef(type: asset.type, id: asset.id, revision: Revision(1)),
    ));
    final archived = _project(store)['personal_asset:${asset.id.value}']!;
    expect(archived.state, 'archived');
    expect(archived.attributes['content'], 'Ten minutes');
    await useCase.updatePersonalContext(UpdatePersonalContextCommand(
      actor: user,
      profileId: EntityId('primary-user'),
      correlationId: 'new-state',
      goalRef: ref,
      goal: 'Study',
      currentState: 'Weekends',
    ));
    expect(
        _project(store).values.where(
            (p) => p.objectType == 'personal_asset' && p.state == 'active'),
        hasLength(1));
    expect(_project(store).values.where((p) => p.objectType == 'goal'),
        hasLength(1));
  });

  test('empty context and D4 fail without a partial write', () async {
    for (final command in <RecordPersonalContextCommand>[
      RecordPersonalContextCommand(
        actor: user,
        profileId: EntityId('primary-user'),
        correlationId: 'empty',
        goal: ' ',
      ),
      RecordPersonalContextCommand(
        actor: user,
        profileId: EntityId('primary-user'),
        correlationId: 'd4',
        goal: 'A goal',
        sensitivity: Sensitivity.d4,
      ),
    ]) {
      await expectLater(
        useCase.recordPersonalContext(command),
        throwsA(isA<StrategyLoopFailure>()),
      );
    }
    expect(store.batches, isEmpty);
  });

  test('agent proposal atomically records strategy and session update',
      () async {
    final result = await useCase.submitProposal(
      SubmitStrategyProposalCommand(
        actor: agent,
        profileId: EntityId('primary-user'),
        correlationId: 'loop-1',
        sessionId: EntityId('session-1'),
        expectedSessionRevision: 1,
        title: 'Run one measurable experiment',
        rationale: 'The goal has an unresolved assumption.',
        goalRefs: <ObjectRef>[goalRef],
        actions: <Map<String, Object?>>[
          <String, Object?>{
            'id': 'action-1',
            'instruction': 'Execute experiment',
          },
        ],
      ),
    );

    expect(result.eventIds, hasLength(2));
    expect(store.batches, hasLength(1));
    expect(store.batches.single.first.eventType, EventTypes.strategyProposed);
    expect(
      store.batches.single.last.eventType,
      EventTypes.agentSessionProposalSubmitted,
    );
    expect(store.batches.single.first.actor.actorType, ActorType.agent);
  });

  test('only the user can accept or activate a strategy', () async {
    final command = DecideStrategyProposalCommand(
      actor: agent,
      profileId: EntityId('primary-user'),
      correlationId: 'loop-1',
      strategyId: EntityId('strategy-1'),
      expectedRevision: 1,
      decision: ProposalDecision.accept,
    );

    await expectLater(
      useCase.decideProposal(command),
      throwsA(
        isA<StrategyLoopFailure>().having(
          (error) => error.code,
          'code',
          StrategyLoopFailureCode.userAuthorityRequired,
        ),
      ),
    );

    await useCase.decideProposal(
      DecideStrategyProposalCommand(
        actor: user,
        profileId: EntityId('primary-user'),
        correlationId: 'loop-1',
        strategyId: EntityId('strategy-1'),
        expectedRevision: 1,
        decision: ProposalDecision.accept,
      ),
    );
    expect(store.batches.single.single.eventType, EventTypes.strategyAccepted);
  });

  test('agent cannot fabricate an execution or outcome', () async {
    final strategyRef = ObjectRef(
      type: 'strategy',
      id: EntityId('strategy-1'),
      revision: Revision(3),
    );
    await expectLater(
      useCase.recordExecution(
        RecordStrategyExecutionCommand(
          actor: agent,
          profileId: EntityId('primary-user'),
          correlationId: 'loop-1',
          strategyRef: strategyRef,
          actionId: EntityId('action-1'),
          status: ExecutionStatus.completed,
        ),
      ),
      throwsA(isA<StrategyLoopFailure>()),
    );
    await expectLater(
      useCase.recordOutcome(
        RecordStrategyOutcomeCommand(
          actor: agent,
          profileId: EntityId('primary-user'),
          correlationId: 'loop-1',
          executionRef: ObjectRef(
            type: 'execution',
            id: EntityId('execution-1'),
            revision: Revision(1),
          ),
          observation: 'Claimed success',
          valence: OutcomeValence.positive,
        ),
      ),
      throwsA(
        isA<StrategyLoopFailure>().having(
          (error) => error.code,
          'code',
          StrategyLoopFailureCode.outcomeAuthorityDenied,
        ),
      ),
    );
  });

  test('explicit feedback atomically pins execution and a neutral observation',
      () async {
    await _activeStrategy(store, user, agent);
    for (final status in <ExecutionStatus>[
      ExecutionStatus.completed,
      ExecutionStatus.skipped,
    ]) {
      final result = await useCase.recordFeedback(
        RecordStrategyFeedbackCommand(
          actor: user,
          profileId: EntityId('primary-user'),
          correlationId: 'feedback-${status.name}',
          strategyRef: ObjectRef(
              type: 'strategy',
              id: EntityId('strategy-1'),
              revision: Revision(3)),
          actionId: EntityId('action-1'),
          status: status,
          note: status == ExecutionStatus.completed ? ' 十分钟有点累 ' : '',
        ),
      );
      final batch = store.batches.last;
      expect(batch.map((event) => event.eventType), <String>[
        EventTypes.executionRecorded,
        EventTypes.outcomeRecorded,
      ]);
      expect(result.eventIds, batch.map((event) => event.eventId));
      expect(batch.first.payload['status'], status.name);
      expect(batch.last.payload['valence'], 'neutral');
      expect(batch.last.payload['metrics'], isEmpty);
      expect(
          batch.last.payload['observation'],
          status == ExecutionStatus.completed
              ? '用户反馈：这一步已完成。 补充：十分钟有点累'
              : '用户反馈：这次没有执行这一步。');
      expect(batch.last.causationId, batch.first.eventId);
      expect(batch.last.sourceRefs.single.toJson(), <String, Object?>{
        'type': 'execution',
        'id': result.executionId.value,
        'revision': 1,
      });
      final projections = _project(store);
      expect(projections['execution:${result.executionId.value}']!.state,
          'recorded');
      expect(
          projections['outcome:${result.outcomeId.value}']!.state, 'recorded');
    }
  });

  test(
      'feedback rejects authority, stale facts and invalid action before writes',
      () async {
    await _activeStrategy(store, user, agent);
    RecordStrategyFeedbackCommand feedback({
      ActorRef? actor,
      String profile = 'primary-user',
      String action = 'action-1',
      int? revision = 3,
      ExecutionStatus status = ExecutionStatus.completed,
      Sensitivity sensitivity = Sensitivity.d1,
      String note = '',
    }) =>
        RecordStrategyFeedbackCommand(
          actor: actor ?? user,
          profileId: EntityId(profile),
          correlationId: 'feedback',
          strategyRef: ObjectRef(
              type: 'strategy',
              id: EntityId('strategy-1'),
              revision: revision == null ? null : Revision(revision)),
          actionId: EntityId(action),
          status: status,
          note: note,
          sensitivity: sensitivity,
        );
    final count = store.batches.length;
    for (final command in <RecordStrategyFeedbackCommand>[
      feedback(actor: agent),
      feedback(revision: null),
      feedback(revision: 2),
      feedback(profile: 'other-user'),
      feedback(action: 'unknown'),
      feedback(status: ExecutionStatus.started),
      feedback(sensitivity: Sensitivity.d4),
      feedback(note: List<String>.filled(4001, 'a').join()),
    ]) {
      await expectLater(
          useCase.recordFeedback(command), throwsA(isA<StrategyLoopFailure>()));
      expect(store.batches, hasLength(count));
    }
    store.rejectNextWrite = true;
    await expectLater(useCase.recordFeedback(feedback()),
        throwsA(isA<PersistenceException>()));
    expect(store.batches, hasLength(count));
    expect(_project(store).values.where((p) => p.objectType == 'execution'),
        isEmpty);
    await useCase.recordFeedback(feedback());
    expect(store.batches, hasLength(count + 1));
    expect(store.batches.last, hasLength(2));
  });

  test('proposal context references must be pinned', () async {
    await expectLater(
      useCase.submitProposal(
        SubmitStrategyProposalCommand(
          actor: agent,
          profileId: EntityId('primary-user'),
          correlationId: 'loop-1',
          sessionId: EntityId('session-1'),
          expectedSessionRevision: 1,
          title: 'Proposal',
          rationale: 'Reason',
          goalRefs: <ObjectRef>[
            ObjectRef(type: 'goal', id: EntityId('goal-1')),
          ],
          actions: <Map<String, Object?>>[
            <String, Object?>{'id': 'a1', 'instruction': 'Act'},
          ],
        ),
      ),
      throwsA(
        isA<StrategyLoopFailure>().having(
          (error) => error.code,
          'code',
          StrategyLoopFailureCode.pinnedReferenceRequired,
        ),
      ),
    );
  });
}

Future<void> _activeStrategy(
    _Store store, ActorRef user, ActorRef agent) async {
  for (final type in <String>[
    EventTypes.strategyProposed,
    EventTypes.strategyAccepted,
    EventTypes.strategyActivated,
  ]) {
    final revision = store.batches.length;
    await store.appendAll(<EventEnvelope>[
      EventEnvelope(
        eventId: 'setup-${revision + 1}',
        eventType: type,
        eventVersion: 1,
        occurredAt: DateTime.utc(2026, 10, 4),
        recordedAt: DateTime.utc(2026, 10, 4),
        actor: revision == 0 ? agent : user,
        subjectRefs: <ObjectRef>[
          ObjectRef(type: 'strategy', id: EntityId('strategy-1')),
          ObjectRef(type: 'profile', id: EntityId('primary-user')),
        ],
        correlationId: 'setup',
        sensitivity: Sensitivity.d1,
        payload: <String, Object?>{
          'expected_revision': revision,
          if (revision == 0)
            'actions': <Object?>[
              <String, Object?>{
                'id': 'action-1',
                'instruction': 'Study ten minutes'
              },
            ],
        },
      ),
    ]);
  }
}

Map<String, ObjectProjection> _project(_Store store) {
  var projections = <String, ObjectProjection>{};
  var seen = <String>{};
  for (final event in store.batches.expand((batch) => batch)) {
    final result =
        reduceCore(projections: projections, seenEventIds: seen, event: event);
    expect(result.disposition, ReductionDisposition.applied);
    projections = result.projections;
    seen = result.seenEventIds;
  }
  return projections;
}

final class _Store implements EventStore {
  final List<List<EventEnvelope>> batches = <List<EventEnvelope>>[];
  bool rejectNextWrite = false;

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    if (rejectNextWrite) {
      rejectNextWrite = false;
      throw const PersistenceException.writeFailed();
    }
    batches.add(List<EventEnvelope>.unmodifiable(events));
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async =>
      batches
          .expand((batch) => batch)
          .where((event) => event.subjectRefs
              .any((ref) => ref.type == subject.type && ref.id == subject.id))
          .toList();
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String nextId(String namespace) => '${namespace}-${++_value}';
}

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 16, 10);
}
