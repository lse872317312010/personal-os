import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/controller/theme_controller.dart';
import 'package:personal_os_app/src/screens/theme_settings_sheet.dart';

void main() {
  testWidgets('theme sheet updates the volatile controller', (tester) async {
    final controller = ThemeController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showThemeSettingsSheet(
                context,
                controller: controller,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-option-dark')));
    await tester.pumpAndSettle();

    expect(controller.mode, ThemeMode.dark);
  });
}
