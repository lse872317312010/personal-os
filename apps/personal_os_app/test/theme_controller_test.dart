import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/controller/theme_controller.dart';

void main() {
  test('ThemeController is volatile and defaults to system', () {
    final controller = ThemeController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(controller.mode, ThemeMode.system);
    controller.setMode(ThemeMode.dark);
    controller.setMode(ThemeMode.dark);

    expect(controller.mode, ThemeMode.dark);
    expect(notifications, 1);
  });
}
