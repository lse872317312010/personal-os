import 'package:flutter/material.dart';

import 'composition/app_composition.dart';
import 'controller/app_controller.dart';
import 'controller/encrypted_event_backup_controller.dart';
import 'controller/strategy_loop_controller.dart';
import 'navigation/app_destination.dart';
import 'screens/screens.dart';

final class PersonalOsApp extends StatefulWidget {
  const PersonalOsApp({required this.composition, super.key});

  final AppComposition composition;

  @override
  State<PersonalOsApp> createState() => _PersonalOsAppState();
}

final class _PersonalOsAppState extends State<PersonalOsApp> {
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Personal OS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff315c4c),
          ),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: AnimatedBuilder(
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
              mode: widget.composition.mode,
            );
          },
        ),
      );
}

final class _UnlockedShell extends StatelessWidget {
  const _UnlockedShell({
    required this.controller,
    required this.strategyController,
    required this.backupController,
    required this.mode,
  });

  final AppController controller;
  final StrategyLoopController strategyController;
  final EncryptedEventBackupController backupController;
  final AppExperienceMode mode;

  @override
  Widget build(BuildContext context) => Scaffold(
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
        body: switch (controller.destination) {
          AppDestination.home => HomeScreen(
              controller: controller,
              backupController: backupController,
              mode: mode,
            ),
          AppDestination.capture => CaptureScreen(
              controller: controller,
              mode: mode,
            ),
          AppDestination.claims => ClaimReviewScreen(controller: controller),
          AppDestination.plan => PlanScreen(controller: controller),
          AppDestination.strategy =>
            StrategyLoopScreen(controller: strategyController),
          AppDestination.tasks => TaskScreen(controller: controller),
          AppDestination.review => ReviewScreen(controller: controller),
        },
        bottomNavigationBar: NavigationBar(
          selectedIndex: _primaryIndex(controller.destination),
          onDestinationSelected: (index) => controller.navigate(
            <AppDestination>[
              AppDestination.home,
              AppDestination.capture,
              AppDestination.strategy,
              AppDestination.tasks,
              AppDestination.review,
            ][index],
          ),
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              label: '分析',
            ),
            NavigationDestination(
              icon: Icon(Icons.psychology_alt_outlined),
              label: '策略',
            ),
            NavigationDestination(
              icon: Icon(Icons.task_alt_outlined),
              label: '行动',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              label: '复盘',
            ),
          ],
        ),
      );
}

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
