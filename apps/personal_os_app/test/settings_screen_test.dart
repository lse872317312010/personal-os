import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_app/src/navigation/app_destination.dart';

void main() {
  testWidgets('settings is reachable from the bottom navigation bar',
      (tester) async {
    await tester.pumpWidget(
      PersonalOsApp(composition: AppComposition.inMemoryDemo()),
    );

    // Unlock the vault first.
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pump();

    // Default destination is home — settings nav should be the 5th item.
    expect(find.text('设置'), findsWidgets);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // Navigate to settings via the bottom nav.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();

    // The AppBar title should reflect the settings destination.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(AppDestination.settings.label),
      ),
      findsOneWidget,
    );
  });

  testWidgets('settings stub shows composition, volatile-demo, roadmap, about',
      (tester) async {
    await tester.pumpWidget(
      PersonalOsApp(composition: AppComposition.inMemoryDemo()),
    );

    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();

    // Composition mode card.
    expect(find.text('运行模式'), findsOneWidget);
    expect(find.textContaining('inMemoryDemo'), findsOneWidget);

    // ADR-0009 §2 volatile-demo card (mirrors home_screen banner).
    expect(find.textContaining('易失·演示数据'), findsOneWidget);
    expect(find.textContaining('永久丢失'), findsOneWidget);

    // Pending features roadmap.
    expect(find.text('功能路线图'), findsOneWidget);
    expect(find.text('主题切换'), findsOneWidget);
    expect(find.text('语言切换'), findsOneWidget);
    expect(find.text('导出 Vault'), findsOneWidget);
    expect(find.text('删除 Vault'), findsOneWidget);
    expect(find.text('跨设备同步'), findsOneWidget);

    // About card.
    expect(find.text('关于'), findsOneWidget);
    expect(find.textContaining('Personal OS'), findsOneWidget);
    expect(find.textContaining('Version: 0.1.0 (stub)'), findsOneWidget);
  });

  testWidgets('settings stub does not crash on vault lock from app bar',
      (tester) async {
    await tester.pumpWidget(
      PersonalOsApp(composition: AppComposition.inMemoryDemo()),
    );

    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();

    // Locking the vault from the settings screen should bring us
    // back to the vault lock screen — the stub must not interfere.
    await tester.tap(find.byKey(const Key('lock-vault')));
    await tester.pump();

    expect(find.text('我的 Personal OS'), findsOneWidget);
    expect(find.text('运行模式'), findsNothing);
  });
}
