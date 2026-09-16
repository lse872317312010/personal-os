import 'package:personal_os_domain/domain.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 16, 8);

  test('strategy preserves pinned context and lineage', () {
    final sessionId = EntityId('session-1');
    final goal = Goal(
      id: EntityId('goal-1'),
      revision: Revision(2),
      statement: 'Improve sleep consistency',
      createdAt: now,
      successCriteria: const <String>['bedtime variance below 30 minutes'],
    );
    final asset = PersonalAsset(
      id: EntityId('asset-1'),
      revision: Revision(3),
      kind: PersonalAssetKind.constraint,
      title: 'Evening schedule',
      content: 'Training ends at 21:00',
      recordedAt: now,
    );
    final strategy = Strategy(
      id: EntityId('strategy-2'),
      revision: Revision(1),
      title: 'Stabilize bedtime',
      rationale: 'Move controllable steps before training.',
      createdAt: now,
      createdBySession: sessionId,
      goalRefs: <ObjectRef>[goal.ref],
      assetRefs: <ObjectRef>[asset.ref],
      parentStrategy: ObjectRef(
        type: 'strategy',
        id: EntityId('strategy-1'),
        revision: Revision(4),
      ),
      actions: <StrategyAction>[
        StrategyAction(
          id: EntityId('action-1'),
          instruction: 'Prepare tomorrow before training',
          successMeasure: 'Preparation completed by 19:45',
        ),
      ],
    );

    final json = strategy.toJson();
    expect(json['created_by_session'], 'session-1');
    expect((json['goal_refs']! as List<Object?>).single, <String, Object?>{
      'type': 'goal',
      'id': 'goal-1',
      'revision': 2,
    });
    expect(
      (json['parent_strategy']! as Map<String, Object?>)['revision'],
      4,
    );
  });

  test('execution and outcome remain separate facts', () {
    final strategyRef = ObjectRef(
      type: 'strategy',
      id: EntityId('strategy-1'),
      revision: Revision(1),
    );
    final execution = Execution(
      id: EntityId('execution-1'),
      strategyRef: strategyRef,
      actionId: EntityId('action-1'),
      status: ExecutionStatus.completed,
      recordedAt: now,
    );
    final outcome = Outcome(
      id: EntityId('outcome-1'),
      executionRef: ObjectRef(
        type: 'execution',
        id: execution.id,
        revision: Revision(1),
      ),
      observation: 'Completed in 12 minutes',
      observedAt: now,
      valence: OutcomeValence.positive,
      metrics: const <String, num>{'duration_minutes': 12},
    );

    expect(execution.toJson()['status'], 'completed');
    expect(outcome.toJson()['metrics'], <String, num>{
      'duration_minutes': 12,
    });
  });

  test('blank agent identity is rejected', () {
    expect(
      () => AgentSession(
        id: EntityId('session-1'),
        agentId: ' ',
        protocolVersion: 'personal-os.mcp.v0',
        openedAt: now,
      ),
      throwsArgumentError,
    );
  });
}
