import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';

void main() {
  testWidgets('offline Chinese MVP completes the guided appearance loop',
      (tester) async {
    final composition = AppComposition.inMemoryDemo();
    await tester.pumpWidget(PersonalOsApp(composition: composition));

    expect(find.textContaining('不上传云端'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pump();

    expect(find.byKey(const Key('synthetic-preview-notice')), findsOneWidget);
    expect(find.textContaining('刷新或关闭页面后清空'), findsOneWidget);

    await tester.tap(find.text('开始首次分析'));
    await tester.pumpAndSettle();
    expect(find.text('内置合成示例'), findsOneWidget);
    expect(find.textContaining('不会读取相册'), findsOneWidget);
    expect(find.byKey(const Key('pick-photo-analyze')), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('analysis-consent')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('analysis-consent')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('analyze-reference')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('analyze-reference')));
    await tester.pumpAndSettle();

    expect(find.text('你的示例建议'), findsOneWidget);
    await tester.tap(find.byKey(const Key('accept-suggestions')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('start-plan')));
    await tester.pump();

    final taskId = composition.controller.result!.taskIds.first;
    await tester.tap(find.byKey(Key('complete-task-$taskId')));
    await tester.pumpAndSettle();
    expect(find.textContaining('行动已记录'), findsOneWidget);

    await tester.tap(find.byKey(const Key('create-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accept-review')));
    await tester.pumpAndSettle();

    expect(find.textContaining('闭环完成'), findsOneWidget);
    expect(composition.controller.completedStep, 5);
  });

  testWidgets('synthetic preview fits phone and desktop browser viewports',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const viewports = <Size>[
      Size(390, 844),
      Size(1280, 800),
      Size(1280, 480),
    ];
    for (final viewport in viewports) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        PersonalOsApp(composition: AppComposition.inMemoryDemo()),
      );
      await tester.tap(find.byKey(const Key('unlock-vault')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('synthetic-preview-notice')), findsOneWidget);
      if (viewport.width >= 900 && viewport.height >= 560) {
        final rail = find.byKey(const Key('desktop-navigation-rail'));
        expect(rail, findsOneWidget);
        expect(find.byKey(const Key('mobile-navigation-bar')), findsNothing);
        expect(
          tester
              .getSize(find.byKey(const Key('responsive-content-frame')))
              .width,
          lessThanOrEqualTo(960),
        );

        await tester.tap(
          find.descendant(of: rail, matching: find.text('行动')),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<NavigationRail>(rail).selectedIndex, 3);
        await tester.tap(
          find.descendant(of: rail, matching: find.text('首页')),
        );
        await tester.pumpAndSettle();
      } else {
        expect(find.byKey(const Key('desktop-navigation-rail')), findsNothing);
        expect(find.byKey(const Key('mobile-navigation-bar')), findsOneWidget);
      }
      expect(
        tester.takeException(),
        isNull,
        reason: 'after unlock at $viewport',
      );

      if (viewport.height < 560) continue;

      await tester.tap(find.text('开始首次分析'));
      await tester.pumpAndSettle();
      expect(find.text('内置合成示例'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'on analysis at $viewport',
      );
    }
  });

  testWidgets('analysis is disabled and explains missing consent in Chinese',
      (tester) async {
    await tester.pumpWidget(
      PersonalOsApp(composition: AppComposition.inMemoryDemo()),
    );
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始首次分析'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('analyze-reference')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('analyze-reference')))
          .onPressed,
      isNull,
    );
    expect(find.text('下一步：先开启本次外貌分析授权。'), findsOneWidget);
  });

  testWidgets('task and review cannot bypass plan and feedback',
      (tester) async {
    final composition = AppComposition.inMemoryDemo();
    await tester.pumpWidget(PersonalOsApp(composition: composition));
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pump();

    await tester.tap(find.text('复盘'));
    await tester.pump();
    expect(find.byKey(const Key('create-review')), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('create-review')))
          .onPressed,
      isNull,
    );
    expect(find.textContaining('先完成或跳过'), findsOneWidget);
  });

  testWidgets('offline strategy preview reports its review prerequisite',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;

    final composition = AppComposition.inMemoryDemo();
    addTearDown(composition.strategyController.dispose);
    await tester.pumpWidget(PersonalOsApp(composition: composition));
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('策略'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('浏览器演示只在当前页面内存运行'),
      findsOneWidget,
    );
    expect(find.textContaining('手机保存资产、策略和真实反馈'), findsNothing);

    await tester.enterText(find.byKey(const Key('agent-id-input')), '');
    await tester.tap(find.byKey(const Key('open-agent-session')));
    await tester.pumpAndSettle();
    expect(find.text('Agent / Harness ID 必须为 1–100 个字符。'), findsOneWidget);
    expect(find.textContaining('strategy.agent_id_invalid'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('agent-id-input')),
      'browser-preview-agent',
    );
    await tester.tap(find.byKey(const Key('open-agent-session')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Session ID:'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('proposal-bundle-input')),
      jsonEncode(<String, Object?>{
        'protocol_version': 'personal-os.mcp.v0',
        'proposal_id': 'browser-preview-revision',
        'session_id': composition.strategyController.sessionId,
        'created_at': '2026-09-25T00:00:00Z',
        'strategy': <String, Object?>{
          'title': 'Revised browser preview strategy',
          'rationale': 'A revision requires a user accepted review.',
          'goal_refs': <Object?>[
            <String, Object?>{
              'type': 'goal',
              'id': 'goal-browser-preview',
              'revision': 1,
            },
          ],
          'asset_refs': <Object?>[],
          'parent_strategy': <String, Object?>{
            'type': 'strategy',
            'id': 'strategy-browser-preview',
            'revision': 1,
          },
          'actions': <Object?>[
            <String, Object?>{
              'id': 'browser-preview-action',
              'instruction': 'Run the bounded browser preview.',
            },
          ],
        },
      }),
    );
    await tester.tap(find.byKey(const Key('import-proposal')));
    await tester.pumpAndSettle();
    expect(
      composition.strategyController.errorCode,
      'strategy.accepted_review_required',
    );
    expect(find.text('修订策略前请先导入并接受一份复盘。'), findsOneWidget);
    expect(find.textContaining('invalid_request'), findsNothing);
    expect(
      find.textContaining('strategy.accepted_review_required'),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('export-context')));
    await tester.pumpAndSettle();
    final bundle = tester
        .widget<SelectableText>(find.byKey(const Key('context-bundle-output')))
        .data!;
    expect(bundle, contains('personal-os.mcp.v0'));
    expect(bundle, contains('"protocol_version"'));
    expect(bundle, contains('"session_id"'));
    expect(tester.takeException(), isNull);
  });
}
