import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';

void main() {
  test('non-Android production platforms fail closed without synthetic access',
      () async {
    final unsupportedPlatforms = TargetPlatform.values
        .where((platform) => platform != TargetPlatform.android)
        .toList(growable: false);

    for (final platform in unsupportedPlatforms) {
      final composition = AppComposition.forTargetPlatform(platform);
      final controller = composition.controller;

      expect(
        composition.mode,
        AppExperienceMode.secureVault,
        reason: '$platform must not enter the synthetic demo by default',
      );
      expect(controller.vaultUnlocked, isFalse);
      expect(controller.sourceAvailable, isFalse);
      expect(controller.modelConfigured, isFalse);
      expect(controller.onDeviceProcessingAvailable, isFalse);
      expect(controller.externalProcessingConfigured, isFalse);
      expect(controller.analysisPreflightReady, isFalse);
      expect(controller.observationCount, 0);

      controller.unlockVault();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.vaultUnlocked, isFalse);
      expect(controller.vaultUnlocking, isFalse);
      expect(controller.errorCode, 'security.unlock_unavailable');
      expect(controller.analysisPreflightReady, isFalse);
      expect(controller.observationCount, 0);
    }
  });

  testWidgets('unsupported production shell stays behind the vault gate',
      (tester) async {
    final composition =
        AppComposition.forTargetPlatform(TargetPlatform.windows);

    await tester.pumpWidget(PersonalOsApp(composition: composition));
    expect(find.text('我的 Personal OS'), findsOneWidget);
    expect(find.text('今天，从一个小改变开始'), findsNothing);

    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pumpAndSettle();

    expect(composition.controller.vaultUnlocked, isFalse);
    expect(composition.controller.errorCode, 'security.unlock_unavailable');
    expect(find.text('我的 Personal OS'), findsOneWidget);
    expect(find.text('今天，从一个小改变开始'), findsNothing);
  });

  test('synthetic demo remains explicit opt-in', () {
    final composition = AppComposition.inMemoryDemo();

    expect(composition.mode, AppExperienceMode.syntheticDemo);
    expect(composition.controller.vaultUnlocked, isFalse);
  });
}
