import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('synthetic demo remains explicit opt-in', () {
    final composition = AppComposition.inMemoryDemo();

    expect(composition.mode, AppExperienceMode.syntheticDemo);
    expect(composition.controller.vaultUnlocked, isFalse);
  });
}
