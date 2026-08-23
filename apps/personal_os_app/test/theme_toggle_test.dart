import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';

void main() {
  testWidgets(
    'theme button opens sheet and selecting dark flips MaterialApp themeMode',
    (tester) async {
      final composition = AppComposition.inMemoryDemo();
      await tester.pumpWidget(
        PersonalOsApp(composition: composition),
      );
      await tester.pump();

      // Vault gate blocks the shell; unlock first.
      await tester.tap(find.byKey(const Key('unlock-vault')));
      await tester.pumpAndSettle();

      // Default mode is system.
      expect(
        (tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode),
        ThemeMode.system,
      );

      // Open the theme settings sheet.
      await tester.tap(find.byKey(const Key('open-theme-settings')));
      await tester.pumpAndSettle();
      expect(find.text('主题'), findsOneWidget);
      expect(find.text('跟随系统'), findsWidgets);

      // Select dark.
      await tester.tap(find.byKey(const Key('theme-option-dark')));
      await tester.pumpAndSettle();

      expect(
        (tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode),
        ThemeMode.dark,
      );
      expect(composition.themeController.mode, ThemeMode.dark);
    },
  );

  testWidgets(
    'selecting light updates MaterialApp and keeps the controller in sync',
    (tester) async {
      final composition = AppComposition.inMemoryDemo();
      await tester.pumpWidget(PersonalOsApp(composition: composition));
      await tester.pump();

      await tester.tap(find.byKey(const Key('unlock-vault')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-theme-settings')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('theme-option-light')));
      await tester.pumpAndSettle();

      expect(
        (tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode),
        ThemeMode.light,
      );
      expect(composition.themeController.mode, ThemeMode.light);
    },
  );

  testWidgets(
    'reopening the sheet shows the previously selected mode as checked',
    (tester) async {
      final composition = AppComposition.inMemoryDemo();
      await tester.pumpWidget(PersonalOsApp(composition: composition));
      await tester.pump();

      await tester.tap(find.byKey(const Key('unlock-vault')));
      await tester.pumpAndSettle();

      // First selection.
      await tester.tap(find.byKey(const Key('open-theme-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('theme-option-dark')));
      await tester.pumpAndSettle();
      expect(composition.themeController.mode, ThemeMode.dark);

      // Reopen.
      await tester.tap(find.byKey(const Key('open-theme-settings')));
      await tester.pumpAndSettle();

      final darkRadio = tester.widget<RadioListTile<ThemeMode>>(
        find.byKey(const Key('theme-option-dark')),
      );
      expect(darkRadio.groupValue, ThemeMode.dark);
      expect(darkRadio.value, ThemeMode.dark);
    },
  );
}
