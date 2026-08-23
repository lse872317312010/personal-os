import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';

/// Verifies ADR-0009 §2 requirements on the home screen:
/// - Demo mode must surface a "易失 · 演示" banner so testers never confuse
///   a process-bound in-memory run with a persistent one.
/// - The first time the user taps the analysis CTA in demo mode, a
///   one-time confirmation dialog appears. Cancelling the dialog stays on
///   the home screen; accepting it navigates to capture AND suppresses the
///   dialog for the rest of the session.
/// - devSqlite / prodEncrypted modes never show the banner nor trigger the
///   dialog: durability means the warning would be misleading.
void main() {
  group('HomeScreen ADR-0009 §2 volatile demo warnings:', () {
    Future<void> unlockHome(WidgetTester tester, AppComposition composition) async {
      await tester.pumpWidget(PersonalOsApp(composition: composition));
      await tester.tap(find.byKey(const Key('unlock-vault')));
      await tester.pump();
    }

    testWidgets('demo mode surfaces 易失·演示 banner before acknowledgement', (tester) async {
      await unlockHome(tester, AppComposition.demo());
      expect(find.byKey(const Key('storage-mode-chip')), findsOneWidget);
      // Banner label is exact-match (no 已确认 suffix yet).
      expect(find.text('易失 · 演示'), findsOneWidget);
      expect(find.textContaining('已确认'), findsNothing);
    });

    testWidgets('tapping CTA in demo mode opens volatile-demo dialog', (tester) async {
      await unlockHome(tester, AppComposition.demo());
      await tester.tap(find.byKey(const Key('start-analysis-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('volatile-demo-dialog')), findsOneWidget);
      expect(find.text('演示模式：数据易失'), findsOneWidget);
    });

    testWidgets('cancelling dialog stays on home and keeps banner unacknowledged', (tester) async {
      await unlockHome(tester, AppComposition.demo());
      await tester.tap(find.byKey(const Key('start-analysis-cta')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('volatile-demo-cancel')));
      await tester.pumpAndSettle();
      // Dialog closed.
      expect(find.byKey(const Key('volatile-demo-dialog')), findsNothing);
      // Still on home (banner keeps the unacknowledged label).
      expect(find.textContaining('易失 · 演示'), findsOneWidget);
      expect(find.textContaining('已确认'), findsNothing);
    });

    testWidgets('accepting dialog navigates to capture AND suppresses future dialogs', (tester) async {
      await unlockHome(tester, AppComposition.demo());
      // First tap: dialog appears.
      await tester.tap(find.byKey(const Key('start-analysis-cta')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('volatile-demo-accept')));
      await tester.pumpAndSettle();
      // Now on capture screen (has blob-reference field from CaptureScreen).
      expect(find.byKey(const Key('blob-reference')), findsOneWidget);
      // Navigate back to home via bottom nav.
      await tester.tap(find.byIcon(Icons.home_outlined));
      await tester.pumpAndSettle();
      // Banner now shows the acknowledged variant.
      expect(find.textContaining('易失 · 演示'), findsOneWidget);
      expect(find.textContaining('已确认'), findsOneWidget);
      // Second tap: NO dialog, jumps directly to capture.
      await tester.tap(find.byKey(const Key('start-analysis-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('volatile-demo-dialog')), findsNothing);
      expect(find.byKey(const Key('blob-reference')), findsOneWidget);
    });

    testWidgets('devSqlite mode shows no volatile banner and no dialog', (tester) async {
      const String fakeDbPath = '/tmp/ci-personal-os-vault.db';
      final AppComposition composition = AppComposition.withSqliteVault(
        driver: DevSqliteInMemoryDriverFactory(),
        databasePath: fakeDbPath,
        mode: CompositionMode.devSqlite,
      );
      await unlockHome(tester, composition);
      expect(find.byKey(const Key('storage-mode-chip')), findsOneWidget);
      expect(find.text('开发模式'), findsOneWidget);
      // No banner, because data is durable.
      expect(find.textContaining('易失 · 演示'), findsNothing);
      // Tapping CTA must go straight to capture without any dialog.
      await tester.tap(find.byKey(const Key('start-analysis-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('volatile-demo-dialog')), findsNothing);
      expect(find.byKey(const Key('blob-reference')), findsOneWidget);
    });

    testWidgets('prodEncrypted mode also shows no volatile banner and no dialog', (tester) async {
      const String fakeDbPath = '/data/data/com.personalos.app/files/vault.enc.db';
      final AppComposition composition = AppComposition.withSqliteVault(
        driver: DevSqliteInMemoryDriverFactory(),
        databasePath: fakeDbPath,
        mode: CompositionMode.prodEncrypted,
      );
      await unlockHome(tester, composition);
      expect(find.text('加密模式'), findsOneWidget);
      expect(find.textContaining('易失 · 演示'), findsNothing);
      await tester.tap(find.byKey(const Key('start-analysis-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('volatile-demo-dialog')), findsNothing);
      expect(find.byKey(const Key('blob-reference')), findsOneWidget);
    });
  });
}
