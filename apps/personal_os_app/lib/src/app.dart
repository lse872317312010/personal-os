import 'dart:async';

import 'package:flutter/material.dart';

import 'agent_interop/agent_reply_inbox.dart';
import 'composition/app_composition.dart';
import 'controller/app_controller.dart';
import 'controller/encrypted_event_backup_controller.dart';
import 'controller/strategy_loop_controller.dart';
import 'navigation/app_destination.dart';
import 'screens/screens.dart';
import 'screens/automatic_strategy_screen.dart';

final class PersonalOsApp extends StatefulWidget {
  const PersonalOsApp({required this.composition, super.key});

  final AppComposition composition;

  @override
  State<PersonalOsApp> createState() => _PersonalOsAppState();
}

/// The Android Vault is foreground-only. Moving the app out of view must
/// invalidate the unlocked in-memory session before any future MCP transport
/// can be considered available.
final class _PersonalOsAppState extends State<PersonalOsApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (widget.composition.controller.vaultUnlocked) {
          widget.composition.controller.lockVault(
            errorCode: 'vault.lifecycle_background',
          );
        }
        return;
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Personal OS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: widget.composition.mode == AppExperienceMode.localAgent ? 'PersonalSC' : null,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff315c4c),
          ),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: widget.composition.automaticAgent != null
            ? AutomaticStrategyScreen(agent: widget.composition.automaticAgent!)
            : AnimatedBuilder(
                animation: widget.composition.controller,
                builder: (context, _) {
                  final controller = widget.composition.controller;
                  if (!controller.vaultUnlocked) {
                    return VaultLockScreen(
                      controller: controller,
                      mode: widget.composition.mode,
                    );
                  }
                  return _UnlockedShell(
                    controller: controller,
                    strategyController: widget.composition.strategyController,
                    backupController: widget.composition.backupController,
                    replyInbox: widget.composition.replyInbox,
                    mode: widget.composition.mode,
                  );
                },
              ),
      );
}

final class _UnlockedShell extends StatefulWidget {
  const _UnlockedShell({
    required this.controller,
    required this.strategyController,
    required this.backupController,
    required this.replyInbox,
    required this.mode,
  });

  final AppController controller;
  final StrategyLoopController strategyController;
  final EncryptedEventBackupController backupController;
  final AgentReplyInboxController replyInbox;
  final AppExperienceMode mode;

  @override
  State<_UnlockedShell> createState() => _UnlockedShellState();
}

final class _UnlockedShellState extends State<_UnlockedShell> {
  AppController get controller => widget.controller;
  StrategyLoopController get strategyController => widget.strategyController;
  EncryptedEventBackupController get backupController =>
      widget.backupController;
  AgentReplyInboxController get replyInbox => widget.replyInbox;
  AppExperienceMode get mode => widget.mode;

  @override
  void initState() {
    super.initState();
    unawaited(replyInbox.receivePendingReply());
    unawaited(strategyController.bootstrap());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: replyInbox,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final useNavigationRail =
                constraints.maxWidth >= 900 && constraints.maxHeight >= 560;
            return Scaffold(
              appBar: AppBar(
                title: Text(controller.destination.label),
                actions: <Widget>[
                  IconButton(
                    key: const Key('lock-vault'),
                    tooltip: '锁定 Vault',
                    onPressed: controller.lockVault,
                    icon: const Icon(Icons.lock_outline),
                  ),
                ],
              ),
              body: Column(
                children: <Widget>[
                  if ((replyInbox.hasPendingReply ||
                          replyInbox.droppedReplyCount > 0 ||
                          replyInbox.replyQueueStorageUnavailable) &&
                      controller.destination != AppDestination.strategy)
                    MaterialBanner(
                      key: const Key('incoming-agent-reply-banner'),
                      content: Text(_agentReplyInboxMessage(replyInbox)),
                      actions: <Widget>[
                        if (replyInbox.hasPendingReply) ...<Widget>[
                          TextButton(
                            onPressed: () =>
                                controller.navigate(AppDestination.strategy),
                            child: const Text('查看回复'),
                          ),
                          TextButton(
                            onPressed: () async {
                              await replyInbox.clearPendingReply();
                            },
                            child: const Text('丢弃'),
                          ),
                        ],
                        if (!replyInbox.hasPendingReply &&
                            replyInbox.replyQueueStorageUnavailable)
                          TextButton(
                            onPressed: () =>
                                controller.navigate(AppDestination.strategy),
                            child: const Text('查看收件箱状态'),
                          ),
                        if (replyInbox.droppedReplyCount > 0)
                          TextButton(
                            onPressed: replyInbox.clearDroppedReplyNotice,
                            child: const Text('知道了'),
                          ),
                      ],
                    ),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        if (useNavigationRail)
                          NavigationRail(
                            key: const Key('desktop-navigation-rail'),
                            selectedIndex:
                                _primaryIndex(controller.destination),
                            labelType: NavigationRailLabelType.all,
                            onDestinationSelected: (index) => controller
                                .navigate(_primaryDestinations[index]),
                            destinations: _navigationRailDestinations,
                          ),
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              key: const Key('responsive-content-frame'),
                              constraints: const BoxConstraints(maxWidth: 960),
                              child: _buildPageBody(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: useNavigationRail
                  ? null
                  : NavigationBar(
                      key: const Key('mobile-navigation-bar'),
                      selectedIndex: _primaryIndex(controller.destination),
                      onDestinationSelected: (index) =>
                          controller.navigate(_primaryDestinations[index]),
                      destinations: _navigationBarDestinations,
                    ),
            );
          },
        ),
      );

  Widget _buildPageBody() => Column(
        children: <Widget>[
          if (mode == AppExperienceMode.syntheticDemo)
            const _SyntheticPreviewNotice(),
          Expanded(
            child: switch (controller.destination) {
              AppDestination.home => HomeScreen(
                  controller: controller,
                  strategyController: strategyController,
                  backupController: backupController,
                  mode: mode,
                ),
              AppDestination.capture => CaptureScreen(
                  controller: controller,
                  mode: mode,
                ),
              AppDestination.claims =>
                ClaimReviewScreen(controller: controller),
              AppDestination.plan => PlanScreen(controller: controller),
              AppDestination.strategy => StrategyLoopScreen(
                  controller: strategyController,
                  replyInbox: replyInbox,
                  mode: mode,
                ),
              AppDestination.tasks => strategyController.strategyId != null
                  ? StrategyLoopScreen(
                      controller: strategyController,
                      replyInbox: replyInbox,
                      mode: mode,
                    )
                  : TaskScreen(controller: controller),
              AppDestination.review => ReviewScreen(controller: controller),
            },
          ),
        ],
      );
}

final class _SyntheticPreviewNotice extends StatelessWidget {
  const _SyntheticPreviewNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('synthetic-preview-notice'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '合成体验：只使用内存演示数据，刷新或关闭页面后清空。'
        '请勿输入真实个人信息；不会上传云端，也不代表真实模型结果。',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

String _agentReplyInboxMessage(AgentReplyInboxController inbox) {
  final messages = <String>[
    if (inbox.hasPendingReply) '收到一条 AI 助手回复。内容暂存在本机加密收件箱中，查看后由你决定是否导入。',
    if (inbox.queuedReplyCount > 0) '另有 ${inbox.queuedReplyCount} 条回复等待处理。',
    if (inbox.droppedReplyCount > 0)
      '收件箱容量不足或保存失败，${inbox.droppedReplyCount} 条新回复未保留，'
          '请回到发送回复的助手重新分享。',
    if (inbox.replyQueueStorageUnavailable)
      '本机加密收件箱暂不可用。已有回复不会被自动删除；新回复可能无法保存，'
          '请先处理当前可见回复，必要时回到助手重新分享。',
  ];
  return messages.join(' ');
}

const _primaryDestinations = <AppDestination>[
  AppDestination.home,
  AppDestination.capture,
  AppDestination.strategy,
  AppDestination.tasks,
  AppDestination.review,
];

const _navigationBarDestinations = <NavigationDestination>[
  NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
  NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), label: '分析'),
  NavigationDestination(icon: Icon(Icons.psychology_alt_outlined), label: '策略'),
  NavigationDestination(icon: Icon(Icons.task_alt_outlined), label: '行动'),
  NavigationDestination(icon: Icon(Icons.insights_outlined), label: '复盘'),
];

const _navigationRailDestinations = <NavigationRailDestination>[
  NavigationRailDestination(
    icon: Icon(Icons.home_outlined),
    label: Text('首页'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.auto_awesome_outlined),
    label: Text('分析'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.psychology_alt_outlined),
    label: Text('策略'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.task_alt_outlined),
    label: Text('行动'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.insights_outlined),
    label: Text('复盘'),
  ),
];

int _primaryIndex(AppDestination destination) => switch (destination) {
      AppDestination.home => 0,
      AppDestination.capture ||
      AppDestination.claims ||
      AppDestination.plan =>
        1,
      AppDestination.strategy => 2,
      AppDestination.tasks => 3,
      AppDestination.review => 4,
    };
