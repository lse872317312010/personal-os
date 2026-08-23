import 'package:flutter/material.dart';

import 'composition/app_composition.dart';
import 'controller/app_controller.dart';
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
              return VaultLockScreen(controller: controller);
            }
            return _UnlockedShell(controller: controller);
          },
        ),
      );
}

final class _UnlockedShell extends StatelessWidget {
  const _UnlockedShell({required this.controller});

  final AppController controller;

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
          AppDestination.home => HomeScreen(controller: controller),
          AppDestination.capture => CaptureScreen(controller: controller),
          AppDestination.claims => ClaimReviewScreen(controller: controller),
          AppDestination.plan => PlanScreen(controller: controller),
          AppDestination.tasks => TaskScreen(controller: controller),
          AppDestination.review => ReviewScreen(controller: controller),
          AppDestination.settings => SettingsScreen(controller: controller),
        },
        bottomNavigationBar: NavigationBar(
          selectedIndex: _primaryIndex(controller.destination),
          onDestinationSelected: (index) => controller.navigate(
            <AppDestination>[
              AppDestination.home,
              AppDestination.capture,
              AppDestination.tasks,
              AppDestination.review,
              AppDestination.settings,
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
              icon: Icon(Icons.task_alt_outlined),
              label: '行动',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              label: '复盘',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              label: '设置',
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
      AppDestination.tasks => 2,
      AppDestination.review => 3,
      AppDestination.settings => 4,
    };
