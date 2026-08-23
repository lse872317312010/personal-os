import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_os_app/src/screens/delete_screen.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';

/// Wave 19c: verifies DeleteScreen wiring to DeleteGuard (Wave 17b).
///
/// These tests do NOT re-verify the guard's state-machine logic — that is
/// already covered by `packages/storage_api/test/delete_guard_test.dart`.
/// Here we only assert the UI wiring:
///   1. CTA disabled on initial render (no boxes checked, no typed text).
///   2. Toggling any single checkbox alone does NOT enable CTA.
///   3. Checking all 3 boxes alone does NOT enable CTA.
///   4. Typing "DELETE" alone (no boxes checked) does NOT enable CTA.
///   5. All 3 boxes + "DELETE" enables CTA.
///   6. Typing lowercase "delete" does NOT enable CTA (case-sensitive).
///   7. Tapping CTA when enabled invokes the callback exactly once.
///   8. Callback returning false surfaces an inline error.
void main() {
  AppComposition composition() => AppComposition.inMemoryDemo();

  Future<void> pumpDelete(
    WidgetTester tester, {
    required Future<bool> Function() onConfirmDelete,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeleteScreen(
          controller: composition().controller,
          onConfirmDelete: onConfirmDelete,
        ),
      ),
    );
  }

  testWidgets('CTA disabled on initial render', (tester) async {
    await pumpDelete(tester, onConfirmDelete: () async => true);

    final cta = tester.widget<FilledButton>(find.byKey(const Key('delete-cta')));
    expect(cta.onPressed, isNull,
        reason: 'delete CTA must be disabled on initial render');
  });

  testWidgets('checking only one box does NOT enable CTA', (tester) async {
    await pumpDelete(tester, onConfirmDelete: () async => true);

    await tester.tap(find.byKey(const Key('delete-check-0')));
    await tester.pump();

    final cta = tester.widget<FilledButton>(find.byKey(const Key('delete-cta')));
    expect(cta.onPressed, isNull,
        reason: 'one checkbox alone must not enable delete');
  });

  testWidgets('checking all 3 boxes alone does NOT enable CTA',
      (tester) async {
    await pumpDelete(tester, onConfirmDelete: () async => true);

    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byKey(Key('delete-check-$i')));
      await tester.pump();
    }

    final cta = tester.widget<FilledButton>(find.byKey(const Key('delete-cta')));
    expect(cta.onPressed, isNull,
        reason: 'checklist complete but no typed DELETE → must stay disabled');
  });

  testWidgets('typing DELETE alone does NOT enable CTA', (tester) async {
    await pumpDelete(tester, onConfirmDelete: () async => true);

    await tester.enterText(
        find.byKey(const Key('delete-typed-confirm')), 'DELETE');
    await tester.pump();

    final cta = tester.widget<FilledButton>(find.byKey(const Key('delete-cta')));
    expect(cta.onPressed, isNull,
        reason: 'typed DELETE but no checkboxes → must stay disabled');
  });

  testWidgets('all 3 boxes + DELETE enables CTA', (tester) async {
    await pumpDelete(tester, onConfirmDelete: () async => true);

    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byKey(Key('delete-check-$i')));
      await tester.pump();
    }
    await tester.enterText(
        find.byKey(const Key('delete-typed-confirm')), 'DELETE');
    await tester.pump();

    final cta = tester.widget<FilledButton>(find.byKey(const Key('delete-cta')));
    expect(cta.onPressed, isNotNull,
        reason: 'all preconditions met → CTA must be enabled');
  });

  testWidgets('lowercase "delete" does NOT enable CTA (case-sensitive)',
      (tester) async {
    await pumpDelete(tester, onConfirmDelete: () async => true);

    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byKey(Key('delete-check-$i')));
      await tester.pump();
    }
    await tester.enterText(
        find.byKey(const Key('delete-typed-confirm')), 'delete');
    await tester.pump();

    final cta = tester.widget<FilledButton>(find.byKey(const Key('delete-cta')));
    expect(cta.onPressed, isNull,
        reason: 'lowercase "delete" must NOT satisfy the case-sensitive check');
  });

  testWidgets('tapping enabled CTA invokes callback exactly once',
      (tester) async {
    var calls = 0;
    await pumpDelete(
      tester,
      onConfirmDelete: () async {
        calls += 1;
        return true;
      },
    );

    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byKey(Key('delete-check-$i')));
      await tester.pump();
    }
    await tester.enterText(
        find.byKey(const Key('delete-typed-confirm')), 'DELETE');
    await tester.pump();

    await tester.tap(find.byKey(const Key('delete-cta')));
    await tester.pumpAndSettle();

    expect(calls, 1,
        reason: 'CTA tap must call onConfirmDelete exactly once');
  });

  testWidgets('callback returning false surfaces inline error', (tester) async {
    await pumpDelete(tester, onConfirmDelete: () async => false);

    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byKey(Key('delete-check-$i')));
      await tester.pump();
    }
    await tester.enterText(
        find.byKey(const Key('delete-typed-confirm')), 'DELETE');
    await tester.pump();

    await tester.tap(find.byKey(const Key('delete-cta')));
    await tester.pumpAndSettle();

    expect(find.textContaining('delete_failed'), findsOneWidget,
        reason: 'false return value must surface an inline error');
  });

  testWidgets('blocker hint text shows when CTA disabled', (tester) async {
    await pumpDelete(tester, onConfirmDelete: () async => true);

    // Initially: 4 blockers (3 unchecked + typed-confirm mismatch)
    expect(find.textContaining('请输入 DELETE'), findsOneWidget,
        reason: 'typed-confirm mismatch hint must show when CTA disabled');
    expect(find.textContaining('未勾选'), findsNWidgets(3),
        reason: 'all 3 checklist blockers must show initially');

    // Check first box: 3 blockers remain
    await tester.tap(find.byKey(const Key('delete-check-0')));
    await tester.pump();
    expect(find.textContaining('未勾选'), findsNWidgets(2));

    // Type DELETE: only 2 unchecked blockers remain
    await tester.enterText(
        find.byKey(const Key('delete-typed-confirm')), 'DELETE');
    await tester.pump();
    expect(find.textContaining('请输入 DELETE'), findsNothing,
        reason: 'typed-confirm hint must clear once user types DELETE');
    expect(find.textContaining('未勾选'), findsNWidgets(2));
  });
}
