import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_app/src/controller/strategy_loop_controller.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_in_memory/in_memory.dart';

void main() {
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
      actionId: 'action-1',
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
            'id': 'action-1',
            'instruction': 'Execute experiment',
          },
        ],
      },
    });
