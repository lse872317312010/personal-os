import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_app/src/controller/strategy_loop_controller.dart';
import 'package:personal_os_app/src/screens/strategy_action_card.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_in_memory/in_memory.dart';

void main() {
  testWidgets(
      'restored multi-action feedback keeps the recorded action visible',
      (tester) async {
    for (final state in <String>['execution-only', 'completed', 'skipped']) {
      final store = InMemoryEventStore();
      final first = AppComposition.inMemoryDemo(eventStore: store);
      final controller = first.strategyController;
      await controller.openOfflineSession(agentId: 'multi-action-agent');
      await controller.importProposal(_proposal(controller.sessionId!,
          proposalId: 'multi-action-plan', multipleActions: true));
      await controller.decideProposal(ProposalDecision.accept);
      await controller.activateStrategy();
      controller.selectAction('second-action');
      if (state == 'execution-only') {
        await controller.recordExecution(
            actionId: 'second-action',
            executionStatus: ExecutionStatus.completed);
      } else {
        await controller.recordFeedback(
            executionStatus: state == 'completed'
                ? ExecutionStatus.completed
                : ExecutionStatus.skipped,
            note: 'Feedback for the second action');
      }
      final executionId = controller.executionId;
      final outcomeId = controller.outcomeId;
      expect(executionId, isNotNull);
      expect(controller.status, StrategyUiStatus.ready);
      controller.dispose();
      first.controller.dispose();

      final second = AppComposition.inMemoryDemo(eventStore: store);
      final restored = second.strategyController;
      await restored.bootstrap();
      expect(restored.selectedActionId, 'second-action', reason: state);
      expect(restored.executionId, executionId);
      expect(restored.outcomeId, outcomeId);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: StrategyActionCard(controller: restored)))));
      expect(
          tester
              .widget<Text>(find.byKey(const Key('strategy-focus-instruction')))
              .data,
          'Report the second experiment',
          reason: state);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      restored.dispose();
      second.controller.dispose();
    }
  });

  test('recreated composition resumes and completes the durable strategy loop',
      () async {
    final store = InMemoryEventStore();
    final first = AppComposition.inMemoryDemo(eventStore: store);
    final firstController = first.strategyController;
    await firstController.openOfflineSession(agentId: 'harness-a');
    final firstSessionId = firstController.sessionId;
    await firstController.importProposal(
      _proposal(firstSessionId!, proposalId: 'proposal-1'),
    );
    await firstController.decideProposal(ProposalDecision.accept);
    await firstController.activateStrategy();
    await firstController.recordExecution(
      actionId: 'action-from-proposal',
      executionStatus: ExecutionStatus.completed,
    );
    await firstController.recordOutcome(
      observation: 'First durable result',
      valence: OutcomeValence.positive,
    );
    final strategyId = firstController.strategyId;
    final executionId = firstController.executionId;
    final outcomeId = firstController.outcomeId;
    firstController.dispose();
    first.controller.dispose();

    final second = AppComposition.inMemoryDemo(eventStore: store);
    final restored = second.strategyController;
    await restored.bootstrap();

    expect(restored.sessionId, firstSessionId);
    expect(restored.agentId, 'harness-a');
    expect(restored.strategyId, strategyId);
    expect(restored.strategyState, 'active');
    expect(
      restored.strategyActions.map((action) => action.id),
      <String>['action-from-proposal'],
    );
    expect(restored.selectedActionId, 'action-from-proposal');
    expect(restored.strategyActions.single.successMeasure,
        'Record the measured result');
    expect(restored.strategyActions.single.dueAt, '2026-10-07T00:00:00Z');
    expect(restored.executionId, executionId);
    expect(restored.outcomeId, outcomeId);
    expect(restored.canCloseSession, isTrue);

    await restored.closeSession();
    expect(restored.hasSession, isFalse);
    restored.dispose();
    second.controller.dispose();

    final third = AppComposition.inMemoryDemo(eventStore: store);
    final afterClose = third.strategyController;
    await afterClose.bootstrap();
    expect(afterClose.hasSession, isFalse);

    await afterClose.openOfflineSession(agentId: 'harness-b');
    expect(afterClose.sessionId, isNot(firstSessionId));
    expect(afterClose.status, StrategyUiStatus.ready);
    afterClose.dispose();
    third.controller.dispose();
  });
}

String _proposal(
  String sessionId, {
  required String proposalId,
  bool multipleActions = false,
}) =>
    jsonEncode(<String, Object?>{
      'protocol_version': 'personal-os.mcp.v0',
      'proposal_id': proposalId,
      'session_id': sessionId,
      'created_at': DateTime.utc(2026, 9, 19).toIso8601String(),
      'strategy': <String, Object?>{
        'title': 'Run one experiment',
        'rationale': 'Measure an unresolved assumption.',
        'goal_refs': <Object?>[
          ObjectRef(
            type: 'goal',
            id: EntityId('goal-1'),
            revision: Revision(1),
          ).toJson(),
        ],
        'actions': <Object?>[
          <String, Object?>{
            'id': 'action-from-proposal',
            'instruction': 'Execute experiment',
            'success_measure': 'Record the measured result',
            'due_at': '2026-10-07T00:00:00Z',
          },
          if (multipleActions)
            <String, Object?>{
              'id': 'second-action',
              'instruction': 'Report the second experiment',
            },
        ],
      },
    });
