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
      const <EventEnvelope>[];
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
