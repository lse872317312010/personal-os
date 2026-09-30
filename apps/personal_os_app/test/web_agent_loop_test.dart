import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/agent_interop/agent_handoff.dart';
import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_app/src/controller/strategy_loop_controller.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';

void main() {
  testWidgets('Web carries personal context through two different assistants',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final composition = AppComposition.inMemoryDemo();
    final controller = composition.strategyController;
    addTearDown(controller.dispose);
    await tester.pumpWidget(PersonalOsApp(composition: composition));
    await _tap(tester, 'unlock-vault');
    await _tap(tester, 'start-personal-strategy-loop');
    await _tap(tester, 'load-demo-personal-context');
    await _tap(tester, 'save-personal-context');
    expect(controller.personalGoal, '一周内建立稳定的学习习惯');
    await tester.enterText(
      find.byKey(const Key('assistant-name-input')),
      'ChatGPT',
    );
    await _tap(tester, 'open-agent-session');
    await _tap(tester, 'copy-agent-handoff');
    expect(copied, contains('工作日晚上有 30 分钟空闲'));
    expect(copied, contains('每天投入不超过 20 分钟'));
    expect(copied, contains('本次任务：提出一份可执行的首次策略'));
    await _tap(tester, 'fill-demo-agent-reply');
    await _tap(tester, 'import-agent-reply');
    final firstStrategy = controller.strategyId;
    expect(controller.hasPendingProposal, isTrue);
    expect(controller.executionId, isNull);
    await _tap(tester, 'accept-proposal');
    await _tap(tester, 'activate-strategy');
    await _tap(tester, 'record-execution');
    await _enter(tester, 'outcome-input', '演示结果：20 分钟负担偏大，下一轮改成 10 分钟。');
    await _tap(tester, 'record-outcome');
    final firstExecution = controller.executionId;
    final firstOutcome = controller.outcomeId;
    await _tap(tester, 'copy-agent-handoff');
    expect(copied, contains('本次任务：只复盘已记录的执行和结果'));
    expect(copied, contains('20 分钟负担偏大'));
    await _tap(tester, 'fill-demo-agent-reply');
    await _tap(tester, 'import-agent-reply');
    expect(controller.hasPendingReview, isTrue);
    await _tap(tester, 'accept-review');
    await _tap(tester, 'close-agent-session');
    await _enter(tester, 'assistant-name-input', 'Another text-capable agent');
    await _tap(tester, 'open-agent-session');
    await _tap(tester, 'copy-agent-handoff');
    expect(copied, contains('依据用户已接受的复盘提出下一轮策略'));
    expect(copied, contains(firstStrategy!));
    expect(copied, contains(firstExecution!));
    expect(copied, contains(firstOutcome!));
    await _tap(tester, 'fill-demo-agent-reply');
    await _tap(tester, 'import-agent-reply');
    expect(controller.errorCode, isNull);
    expect(controller.parentStrategyRef, 'strategy:$firstStrategy@3');
    expect(controller.executionId, isNull);
    expect(controller.outcomeId, isNull);
    expect(controller.reviewId, isNull);
    await _tap(tester, 'accept-proposal');
    await _tap(tester, 'activate-strategy');
    await _tap(tester, 'record-execution');
    await _enter(tester, 'outcome-input', '演示结果：10 分钟更容易完成。');
    await _tap(tester, 'record-outcome');
    expect(controller.executionId, isNot(firstExecution));
    expect(controller.outcomeId, isNot(firstOutcome));
    await _tap(tester, 'copy-agent-handoff');
    expect(copied, contains('本次任务：只复盘已记录的执行和结果'));
    final objects = controller.contextRecords;
    int count(String type) => objects
        .where((record) => (record['ref'] as Map)['type'] == type)
        .length;
    expect(count('strategy'), 2);
    expect(count('execution'), 2);
    expect(count('outcome'), 2);
    expect(count('review'), 1);
    expect(tester.takeException(), isNull);
  });

  test('a revised strategy needs a review of that exact parent', () async {
    final app = AppComposition.inMemoryDemo();
    final controller = app.strategyController;
    addTearDown(controller.dispose);
    await controller.savePersonalContext(goal: 'A measurable goal');
    await controller.openOfflineSession(agentId: 'first-agent');
    await controller.exportContext();
    await controller
        .importProposal(buildDemoAgentReply(controller.contextBundle!));
    await controller.decideProposal(ProposalDecision.accept);
    await controller.activateStrategy();
    await controller.recordExecution(
      actionId: 'demo-action-v1',
      executionStatus: ExecutionStatus.completed,
    );
    await controller.recordOutcome(
      observation: 'A user-recorded result',
      valence: OutcomeValence.mixed,
    );
    await controller.exportContext();
    await controller
        .importReview(buildDemoAgentReply(controller.contextBundle!));
    await controller.decideReview(ReviewDecision.accept);
    await controller.exportContext();
    final valid = buildDemoAgentReply(controller.contextBundle!);
    final wrongParent = jsonDecode(valid) as Map<String, Object?>;
    ((wrongParent['strategy'] as Map)['parent_strategy'] as Map)['id'] =
        'unreviewed-strategy';
    await controller.importProposal(jsonEncode(wrongParent));
    expect(controller.errorCode, 'strategy.accepted_review_required');
    expect(controller.reviewState, 'accepted');
    await controller.importProposal(valid);
    expect(controller.status, StrategyUiStatus.ready);
    expect(controller.executionId, isNull);
    expect(controller.outcomeId, isNull);
    expect(controller.reviewId, isNull);
    controller.reset();
    await controller.bootstrap();
    expect(controller.reviewId, isNull);
    expect(controller.executionId, isNull);
  });

  test('handoff includes all pages of personal context', () async {
    final app = AppComposition.inMemoryDemo();
    final controller = app.strategyController;
    addTearDown(controller.dispose);
    for (var index = 0; index < 105; index++) {
      await controller.savePersonalContext(goal: 'Goal $index');
    }
    await controller.openOfflineSession(agentId: 'text-agent');
    await controller.exportContext();
    final bundle = jsonDecode(controller.contextBundle!) as Map;
    expect(bundle['has_more'], isFalse);
    expect(bundle['objects'], hasLength(105));
  });
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  if (key != 'unlock-vault') {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}
