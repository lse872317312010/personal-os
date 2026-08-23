import 'package:flutter/material.dart';

import 'composition/app_composition.dart';
import 'controller/app_controller.dart';
import 'controller/theme_controller.dart';
import 'navigation/app_destination.dart';
import 'screens/screens.dart';
import 'screens/theme_settings_sheet.dart';

final class PersonalOsApp extends StatefulWidget {
  const PersonalOsApp({required this.composition, super.key});

  final AppComposition composition;

  @override
  State<PersonalOsApp> createState() => _PersonalOsAppState();
}

final class _PersonalOsAppState extends State<PersonalOsApp> {
  @override
  Widget build(BuildContext context) {
    final composition = widget.composition;
    return AnimatedBuilder(
      animation: composition.themeController,
      builder: (context, _) => MaterialApp(
        title: 'Personal OS',
        debugShowCheckedModeBanner: false,
        theme: _lightTheme,
        darkTheme: _darkTheme,
        themeMode: composition.themeController.mode,
        home: AnimatedBuilder(
          animation: composition.controller,
          builder: (context, _) {
            final controller = composition.controller;
            if (!controller.vaultUnlocked) {
              return VaultLockScreen(controller: controller);
            }
            return _UnlockedShell(
              controller: controller,
              themeController: composition.themeController,
            );
          },
        ),
      ),
    );
  }
}

final ThemeData _lightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff315c4c),
    brightness: Brightness.light,
  ),
  useMaterial3: true,
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
);

final ThemeData _darkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff315c4c),
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
);

final class _UnlockedShell extends StatelessWidget {
  const _UnlockedShell({
    required this.controller,
    required this.themeController,
  });

  final AppController controller;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(controller.destination.label),
          actions: <Widget>[
            IconButton(
              key: const Key('open-theme-settings'),
              tooltip: '主题',
              onPressed: () =>
                  showThemeSettingsSheet(context, controller: themeController),
              icon: const Icon(Icons.palette_outlined),
            ),
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
        },
        bottomNavigationBar: NavigationBar(
          selectedIndex: _primaryIndex(controller.destination),
          onDestinationSelected: (index) => controller.navigate(
            <AppDestination>[
              AppDestination.home,
              AppDestination.capture,
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
      AppDestination.tasks => 2,
      AppDestination.review => 3,
    };
