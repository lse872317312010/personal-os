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
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
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
        },
        bottomNavigationBar: NavigationBar(
          selectedIndex: controller.destination.index,
          onDestinationSelected: (index) =>
              controller.navigate(AppDestination.values[index]),
          destinations: AppDestination.values
              .map(
                (destination) => NavigationDestination(
                  icon: Icon(_iconFor(destination)),
                  label: destination.label,
                ),
              )
              .toList(growable: false),
        ),
      );
}

IconData _iconFor(AppDestination destination) => switch (destination) {
      AppDestination.home => Icons.home_outlined,
      AppDestination.capture => Icons.add_a_photo_outlined,
      AppDestination.claims => Icons.fact_check_outlined,
      AppDestination.plan => Icons.route_outlined,
      AppDestination.tasks => Icons.task_alt_outlined,
      AppDestination.review => Icons.insights_outlined,
    };
