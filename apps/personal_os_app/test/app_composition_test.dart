import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowsTestChannel = MethodChannel('personal_os/test/windows-security');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(windowsTestChannel, null);
  });

  test('unsupported production platforms fail closed without synthetic access',
      () async {
    final unsupportedPlatforms = TargetPlatform.values
        .where(
          (platform) =>
              platform != TargetPlatform.android &&
              platform != TargetPlatform.windows,
        )
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

      await expectLater(
        composition.eventStore.appendAll(const []),
        throwsA(
          isA<PersistenceException>().having(
            (error) => error.code,
            'code',
            PersistenceErrorCode.writeFailed,
          ),
        ),
      );
      await expectLater(
        composition.eventStore.readById('unsupported-platform-event'),
        throwsA(
          isA<PersistenceException>().having(
            (error) => error.code,
            'code',
            PersistenceErrorCode.readFailed,
          ),
        ),
      );

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

  test('Windows authentication cannot bypass unavailable encrypted storage',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(windowsTestChannel, (call) async {
      calls.add(call);
      if (call.method == 'authenticate') {
        return <String, Object?>{
          'id': 'windows-auth-ticket-1',
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        };
      }
      throw PlatformException(code: 'security.provider_unavailable');
    });

    final composition = AppComposition.windowsSecureBoundary(
      securityChannel: windowsTestChannel,
    );
    final controller = composition.controller;

    expect(composition.mode, AppExperienceMode.secureVault);
    expect(controller.sourceAvailable, isFalse);
    expect(controller.modelConfigured, isFalse);
    expect(controller.vaultUnlocked, isFalse);

    controller.unlockVault();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(calls.map((call) => call.method), <String>['authenticate']);
    expect(controller.vaultUnlocked, isFalse);
    expect(controller.vaultUnlocking, isFalse);
    expect(controller.errorCode, 'security.provider_unavailable');
    expect(controller.analysisPreflightReady, isFalse);
    expect(controller.observationCount, 0);

    await expectLater(
      composition.eventStore.appendAll(const []),
      throwsA(
        isA<PersistenceException>().having(
          (error) => error.code,
          'code',
          PersistenceErrorCode.writeFailed,
        ),
      ),
    );
  });

  testWidgets('Windows production shell stays behind the vault gate',
      (tester) async {
    final composition =
        AppComposition.forTargetPlatform(TargetPlatform.windows);

    await tester.pumpWidget(PersonalOsApp(composition: composition));
    expect(find.text('我的 Personal OS'), findsOneWidget);
    expect(find.text('今天，从一个小改变开始'), findsNothing);

    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pumpAndSettle();

    expect(composition.controller.vaultUnlocked, isFalse);
    expect(composition.controller.errorCode, 'security.provider_unavailable');
    expect(find.byKey(const Key('unlock-error')), findsOneWidget);
    expect(find.text('当前平台的安全服务尚未配置。'), findsOneWidget);
    expect(find.text('我的 Personal OS'), findsOneWidget);
    expect(find.text('今天，从一个小改变开始'), findsNothing);
  });

  test('current production composition is never synthetic by default', () {
    final composition = AppComposition.forCurrentPlatform();

    expect(composition.mode, AppExperienceMode.secureVault);
  });

  test('synthetic demo remains explicit opt-in', () {
    final composition = AppComposition.inMemoryDemo();

    expect(composition.mode, AppExperienceMode.syntheticDemo);
    expect(composition.controller.vaultUnlocked, isFalse);
  });
}
