import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';

import 'package:personal_os_app/src/agent_interop/agent_reply_inbox.dart';
import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_app/src/screens/strategy_loop_screen.dart';

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

    await tester.scrollUntilVisible(
      find.text('开始首次分析'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
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

      await tester.scrollUntilVisible(
        find.text('开始首次分析'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('开始首次分析')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
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
    await tester.scrollUntilVisible(
      find.text('开始首次分析'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
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

    await tester.enterText(
      find.byKey(const Key('assistant-name-input')),
      'containerized-custom-harness',
    );
    await tester.tap(find.byKey(const Key('open-agent-session')));
    await tester.pumpAndSettle();
    expect(
      composition.strategyController.agentId,
      'containerized-custom-harness',
    );
    expect(composition.strategyController.contextBundle, isNotNull);
    expect(find.byKey(const Key('copy-agent-handoff')), findsOneWidget);
    expect(find.textContaining('Session ID:'), findsNothing);
    expect(find.byKey(const Key('review-bundle-input')), findsNothing);

    await tester.tap(find.byKey(const Key('advanced-agent-options')));
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
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('import-proposal'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-proposal')));
    await tester.pumpAndSettle();
    expect(
      composition.strategyController.errorCode,
      'strategy.accepted_review_required',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('修订策略前请先导入并接受一份复盘。'), findsOneWidget);
    expect(find.textContaining('invalid_request'), findsNothing);
    expect(
      find.textContaining('strategy.accepted_review_required'),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('export-context')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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

  testWidgets(
    'a rejected replacement reply keeps the prior proposal and stays visible',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;

      final composition = AppComposition.inMemoryDemo();
      final controller = composition.strategyController;
      addTearDown(controller.dispose);
      await controller.openOfflineSession(agentId: 'replacement-test-harness');
      final sessionId = controller.sessionId!;
      await controller.importProposal(jsonEncode(<String, Object?>{
        'protocol_version': 'personal-os.mcp.v0',
        'proposal_id': 'original-proposal',
        'session_id': sessionId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'strategy': <String, Object?>{
          'title': 'Original proposal',
          'rationale': 'This is the proposal that remains pending.',
          'goal_refs': <Object?>[
            <String, Object?>{
              'type': 'goal',
              'id': 'goal-browser-preview',
              'revision': 1,
            },
          ],
          'actions': <Object?>[
            <String, Object?>{
              'id': 'original-action',
              'instruction': 'Complete the original action.',
            },
          ],
        },
      }));
      final originalStrategyId = controller.strategyId;

      await tester.pumpWidget(PersonalOsApp(composition: composition));
      await tester.tap(find.byKey(const Key('unlock-vault')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('策略'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('与 AI 协作'));
      await tester.tap(find.text('与 AI 协作'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('agent-reply-input')),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      final replacement = jsonEncode(<String, Object?>{
        'protocol_version': 'personal-os.mcp.v0',
        'proposal_id': 'rejected-replacement',
        'session_id': sessionId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'strategy': <String, Object?>{
          'title': 'Rejected replacement',
          'rationale': 'This revision has no accepted review.',
          'goal_refs': <Object?>[
            <String, Object?>{
              'type': 'goal',
              'id': 'goal-browser-preview',
              'revision': 1,
            },
          ],
          'parent_strategy': <String, Object?>{
            'type': 'strategy',
            'id': 'previous-strategy',
            'revision': 1,
          },
          'actions': <Object?>[
            <String, Object?>{
              'id': 'replacement-action',
              'instruction': 'Run the rejected replacement.',
            },
          ],
        },
      });
      await tester.enterText(
        find.byKey(const Key('agent-reply-input')),
        replacement,
      );
      await tester.tap(find.byKey(const Key('import-agent-reply')));
      await tester.pumpAndSettle();

      expect(controller.errorCode, 'strategy.accepted_review_required');
      expect(controller.strategyId, originalStrategyId);
      expect(controller.proposalTitle, 'Original proposal');
      expect(controller.hasPendingProposal, isTrue);
      expect(
        controller.strategyActions.map((action) => action.id),
        <String>['original-action'],
      );
      expect(controller.selectedActionId, 'original-action');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('agent-reply-input')))
            .controller!
            .text,
        replacement,
      );
      expect(
        find.text('建议已导入，请查看内容并决定是否接受。'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'manual import preserves a different reply shared at the same time',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;

      final composition = AppComposition.inMemoryDemo();
      final controller = composition.strategyController;
      addTearDown(controller.dispose);
      await controller.openOfflineSession(agentId: 'manual-import-test');

      final replyPort = _ReplyInboxPort();
      final inbox = AgentReplyInboxController(
        port: replyPort,
        isVaultUnlocked: () => true,
      );
      addTearDown(inbox.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StrategyLoopScreen(
              controller: controller,
              mode: AppExperienceMode.syntheticDemo,
              replyInbox: inbox,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('agent-reply-input')),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      final manualProposal = jsonEncode(<String, Object?>{
        'protocol_version': 'personal-os.mcp.v0',
        'proposal_id': 'manual-import-proposal',
        'session_id': controller.sessionId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'strategy': <String, Object?>{
          'title': 'Manual strategy',
          'rationale': 'Keep the other shared reply available.',
          'goal_refs': <Object?>[
            <String, Object?>{
              'type': 'goal',
              'id': 'goal-browser-preview',
              'revision': 1,
            },
          ],
          'actions': <Object?>[
            <String, Object?>{
              'id': 'manual-action',
              'instruction': 'Run the manual strategy.',
            },
          ],
        },
      });
      await tester.enterText(
        find.byKey(const Key('agent-reply-input')),
        manualProposal,
      );
      await replyPort.share('reply from Android share');
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('agent-reply-input')))
            .controller!
            .text,
        manualProposal,
      );

      await tester.ensureVisible(find.byKey(const Key('import-agent-reply')));
      await tester.tap(find.byKey(const Key('import-agent-reply')));
      await tester.pumpAndSettle();

      expect(controller.hasPendingProposal, isTrue);
      expect(inbox.pendingReply, 'reply from Android share');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('agent-reply-input')))
            .controller!
            .text,
        'reply from Android share',
      );
    },
  );

  testWidgets(
    'copying a handoff refreshes context with the latest recorded outcome',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;

      String? clipboardText;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments as Map<Object?, Object?>;
            clipboardText = arguments['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final composition = AppComposition.inMemoryDemo();
      final controller = composition.strategyController;
      addTearDown(controller.dispose);
      await controller.savePersonalContext(goal: 'Measure the latest result');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StrategyLoopScreen(
              controller: controller,
              mode: AppExperienceMode.syntheticDemo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-agent-session')));
      await tester.pumpAndSettle();

      final oldBundle = controller.contextBundle!;
      final sessionId = controller.sessionId!;
      await controller.importProposal(jsonEncode(<String, Object?>{
        'protocol_version': 'personal-os.mcp.v0',
        'proposal_id': 'fresh-context-proposal',
        'session_id': sessionId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'strategy': <String, Object?>{
          'title': 'Measure the latest result',
          'rationale': 'Compare the action with its real outcome.',
          'goal_refs': <Object?>[
            <String, Object?>{
              'type': 'goal',
              'id': 'goal-browser-preview',
              'revision': 1,
            },
          ],
          'actions': <Object?>[
            <String, Object?>{
              'id': 'fresh-context-action',
              'instruction': 'Run one measurable experiment.',
            },
          ],
        },
      }));
      await controller.decideProposal(ProposalDecision.accept);
      await controller.activateStrategy();
      await controller.recordExecution(
        actionId: 'fresh-context-action',
        executionStatus: ExecutionStatus.completed,
      );
      await controller.recordOutcome(
        observation: 'Outcome only present after refreshing context.',
        valence: OutcomeValence.positive,
      );
      expect(controller.contextBundle, oldBundle);

      final copyButton = find.byKey(const Key('copy-agent-handoff'));
      await tester.ensureVisible(copyButton);
      await tester.tap(copyButton);
      await tester.pumpAndSettle();

      expect(controller.contextBundle, isNot(oldBundle));
      expect(
        clipboardText,
        contains('Outcome only present after refreshing context.'),
      );
    },
  );

  testWidgets(
    'a shared reply stays unread while locked and opens in its restored session',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;

      final replyPort = _ReplyInboxPort();
      final composition = AppComposition.inMemoryDemo(
        replyInboxPort: replyPort,
      );
      addTearDown(composition.strategyController.dispose);
      addTearDown(composition.replyInbox.dispose);

      await tester.pumpWidget(PersonalOsApp(composition: composition));
      await tester.tap(find.byKey(const Key('unlock-vault')));
      await tester.pumpAndSettle();

      final navigation = find.byKey(const Key('mobile-navigation-bar'));
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('策略')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-agent-session')));
      await tester.pumpAndSettle();
      expect(composition.strategyController.hasSession, isTrue);
      final sessionId = composition.strategyController.sessionId!;

      await tester.tap(
        find.descendant(of: navigation, matching: find.text('首页')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lock-vault')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unlock-vault')), findsOneWidget);

      final reply = jsonEncode(<String, Object?>{
        'protocol_version': 'personal-os.mcp.v0',
        'proposal_id': 'shared-proposal',
        'session_id': sessionId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'strategy': <String, Object?>{
          'title': 'One shared experiment',
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
              'id': 'shared-action',
              'instruction': 'Try one small step',
            },
          ],
        },
      });
      await replyPort.share(reply);
      await tester.pumpAndSettle();

      // The text stays in the native queue while the Vault remains locked.
      expect(replyPort.hasPendingReply, isTrue);
      expect(find.text(reply), findsNothing);
      await tester.tap(find.byKey(const Key('unlock-vault')));
      await tester.pumpAndSettle();
      expect(replyPort.hasPendingReply, isTrue);

      final banner = find.byKey(const Key('incoming-agent-reply-banner'));
      expect(banner, findsOneWidget);
      expect(find.text(reply), findsNothing);
      await tester.tap(
        find.descendant(of: banner, matching: find.text('查看回复')),
      );
      await tester.pumpAndSettle();

      final replyField = find.byKey(const Key('agent-reply-input'));
      await tester.scrollUntilVisible(
        replyField,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<TextField>(replyField).controller!.text,
        reply,
      );
      expect(composition.strategyController.hasPendingProposal, isFalse);
      expect(replyPort.hasPendingReply, isTrue);

      final editedReply = reply.replaceAll(
        'Measure the result.',
        'Measure the result carefully.',
      );
      await tester.enterText(replyField, editedReply);
      final importReply = find.byKey(const Key('import-agent-reply'));
      await tester.ensureVisible(importReply);
      await tester.tap(importReply);
      await tester.pumpAndSettle();

      expect(composition.strategyController.hasPendingProposal, isTrue);
      expect(composition.strategyController.strategyState, 'proposed');
      expect(replyPort.hasPendingReply, isFalse);
      expect(composition.strategyController.hasSession, isTrue);
    },
  );
}

final class _ReplyInboxPort implements AgentReplyInboxPort {
  final List<String> _pending = <String>[];
  bool get hasPendingReply => _pending.isNotEmpty;
  AgentReplyAvailableHandler? _handler;

  @override
  Future<String?> peekPendingReply() async =>
      _pending.isEmpty ? null : _pending.first;

  @override
  Future<bool> acknowledgePendingReply() async {
    if (_pending.isNotEmpty) _pending.removeAt(0);
    return true;
  }

  @override
  Future<int> pendingReplyCount() async => _pending.length;

  @override
  Future<int> takeDroppedReplyCount() async => 0;

  @override
  Future<bool> replyQueueStorageReady() async => true;

  @override
  void setReplyAvailableHandler(AgentReplyAvailableHandler? handler) {
    _handler = handler;
  }

  Future<void> share(String reply) async {
    _pending.add(reply);
    final handler = _handler;
    if (handler != null) await handler();
  }
}
