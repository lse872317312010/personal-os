import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/agent_interop/agent_handoff.dart';
import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_in_memory/in_memory.dart';

void main() {
  testWidgets('the suggested action and start button fit the first screen',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in <Size>[const Size(390, 844), const Size(1280, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final app = AppComposition.inMemoryDemo();
      addTearDown(app.strategyController.dispose);
      await _prepare(app);
      await tester.pumpWidget(PersonalOsApp(composition: app));
      await tester.tap(find.byKey(const Key('unlock-vault')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-current-agent-action')));
      await tester.pumpAndSettle();

      final instruction = find.byKey(const Key('strategy-focus-instruction'));
      final start = find.byKey(const Key('accept-proposal'));
      expect(instruction, findsOneWidget);
      expect(find.textContaining('做到什么算完成'), findsOneWidget);
      expect(find.textContaining('2026/10/7'), findsOneWidget);
      expect(tester.getTopLeft(instruction).dy, greaterThan(0));
      expect(tester.getBottomRight(start).dy, lessThan(size.height - 60));
      expect(find.byKey(const Key('agent-reply-input')), findsNothing);

      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(app.strategyController.strategyState, 'active');
      expect(app.strategyController.executionId, isNull);

      final all = find.byKey(const Key('strategy-all-actions'));
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pumpAndSettle();
      final second = find.byKey(const Key('choose-strategy-action-second'));
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(app.strategyController.selectedActionId, 'second');
      expect(find.text('把困难整理成一个待解决的问题。'), findsWidgets);
      final record = find.byKey(const Key('record-execution'));
      await tester.ensureVisible(record);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(record);
      await tester.pumpAndSettle();
      expect(app.strategyController.executionId, isNotNull);
      expect(app.strategyController.outcomeId, isNull);
      expect(find.byKey(const Key('outcome-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('unlock restores the actionable plan directly on the home page',
      (tester) async {
    final store = InMemoryEventStore();
    final first = AppComposition.inMemoryDemo(eventStore: store);
    await _prepare(first);
    first.strategyController.dispose();
    final restored = AppComposition.inMemoryDemo(eventStore: store);
    addTearDown(restored.strategyController.dispose);
    await tester.pumpWidget(PersonalOsApp(composition: restored));
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('strategy-action-focus')), findsOneWidget);
    expect(find.textContaining('今晚用十分钟'), findsOneWidget);
    expect(restored.strategyController.executionId, isNull);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _prepare(AppComposition app) async {
  final controller = app.strategyController;
  await controller.savePersonalContext(goal: '建立学习习惯');
  await controller.openOfflineSession(agentId: 'text-agent');
  await controller.exportContext();
  final reply =
      jsonDecode(buildDemoAgentReply(controller.contextBundle!)) as Map;
  final strategy = reply['strategy'] as Map;
  strategy['title'] = '一周学习计划';
  strategy['actions'] = <Object?>[
    <String, Object?>{
      'id': 'first',
      'instruction': '今晚用十分钟复习一个知识点，记下遇到的困难。',
      'success_measure': '能说出一个知识点，并记下一条困难。',
      'due_at': '2026-10-07T00:00:00Z',
    },
    <String, Object?>{
      'id': 'second',
      'instruction': '把困难整理成一个待解决的问题。',
    },
  ];
  await controller.importProposal(jsonEncode(reply));
}
