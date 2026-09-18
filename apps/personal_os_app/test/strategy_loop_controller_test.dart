import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_app/src/controller/strategy_loop_controller.dart';

void main() {
  test('opening another session preserves the current Harness identity', () async {
    final app = AppComposition.inMemoryDemo();
    final controller = app.strategyController;
    addTearDown(controller.dispose);
    await controller.openOfflineSession(agentId: 'harness-a');
    expect(controller.status, StrategyUiStatus.ready);
    final sessionId = controller.sessionId;

    await controller.openOfflineSession(agentId: 'harness-b');

    expect(controller.errorCode, 'strategy.session_already_open');
    expect(controller.sessionId, sessionId);
    expect(controller.agentId, 'harness-a');
    await controller.closeSession();
    expect(controller.hasSession, isFalse);
    await controller.openOfflineSession(agentId: 'harness-b');
    expect(controller.status, StrategyUiStatus.ready);
    expect(controller.agentId, 'harness-b');
    expect(controller.sessionId, isNot(sessionId));
  });

  test('overlapping session opens cannot change the in-flight identity',
      () async {
    final app = AppComposition.inMemoryDemo();
    final controller = app.strategyController;
    addTearDown(controller.dispose);
    final first = controller.openOfflineSession(agentId: 'harness-a');
    await controller.openOfflineSession(agentId: 'harness-b');
    await first;

    expect(controller.status, StrategyUiStatus.ready);
    expect(controller.agentId, 'harness-a');
    await controller.closeSession();
    expect(controller.status, StrategyUiStatus.ready);
    expect(controller.hasSession, isFalse);
  });

  test('a new execution requires its own outcome before handoff', () async {
    final app = AppComposition.inMemoryDemo();
    final controller = app.strategyController;
    addTearDown(controller.dispose);
    await controller.openOfflineSession(agentId: 'harness-a');
    await controller.importProposal(jsonEncode(<String, Object?>{
      'protocol_version': 'personal-os.mcp.v0',
      'proposal_id': 'proposal-1',
      'session_id': controller.sessionId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'strategy': <String, Object?>{
        'title': 'One experiment',
        'rationale': 'Measure the result.',
        'goal_refs': <Object?>[
          ObjectRef(
            type: 'goal',
            id: EntityId('goal-1'),
            revision: Revision(1),
          ).toJson(),
        ],
        'actions': <Object?>[
          <String, Object?>{
            'id': 'action-1',
            'instruction': 'Execute experiment',
          },
        ],
      },
    }));
    expect(controller.status, StrategyUiStatus.ready);
    await controller.decideProposal(ProposalDecision.accept);
    await controller.activateStrategy();
    await controller.recordExecution(
      actionId: 'action-1',
      executionStatus: ExecutionStatus.completed,
    );
    await controller.recordOutcome(
      observation: 'First result',
      valence: OutcomeValence.positive,
    );
    expect(controller.status, StrategyUiStatus.ready);
    expect(controller.canCloseSession, isTrue);
    final firstExecution = controller.executionId;

    await controller.recordExecution(
      actionId: 'action-1',
      executionStatus: ExecutionStatus.completed,
    );

    expect(controller.status, StrategyUiStatus.ready);
    expect(controller.executionId, isNot(firstExecution));
    expect(controller.outcomeId, isNull);
    expect(controller.canCloseSession, isFalse);
    await controller.closeSession();
    expect(controller.errorCode, 'strategy.loop_must_finish_before_handoff');
    expect(controller.hasSession, isTrue);
    await controller.recordOutcome(
      observation: 'Second result',
      valence: OutcomeValence.neutral,
    );
    expect(controller.status, StrategyUiStatus.ready);
    expect(controller.canCloseSession, isTrue);
  });
}
