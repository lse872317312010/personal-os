import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/controller/theme_controller.dart';

void main() {
  group('ThemeController', () {
    test('defaults to ThemeMode.system', () {
      expect(ThemeController().mode, ThemeMode.system);
    });

    test('respects initial value', () {
      expect(
        ThemeController(initial: ThemeMode.dark).mode,
        ThemeMode.dark,
      );
    });

    test('setMode updates value and notifies listeners once', () {
      final controller = ThemeController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setMode(ThemeMode.dark);
      expect(controller.mode, ThemeMode.dark);
      expect(notifications, 1);
    });

    test('setMode is a no-op for the current value', () {
      final controller = ThemeController(initial: ThemeMode.dark);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setMode(ThemeMode.dark);
      expect(controller.mode, ThemeMode.dark);
      expect(notifications, 0);
    });

    test('cycling through all three modes emits two notifications', () {
      final controller = ThemeController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setMode(ThemeMode.light);
      controller.setMode(ThemeMode.dark);
      controller.setMode(ThemeMode.system);

      expect(controller.mode, ThemeMode.system);
      expect(notifications, 3);
    });

    test('dispose removes listeners without throwing', () {
      final controller = ThemeController();
      controller.addListener(() {});
      expect(controller.dispose, returnsNormally);
    });
  });
}
