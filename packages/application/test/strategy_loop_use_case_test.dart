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

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
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
