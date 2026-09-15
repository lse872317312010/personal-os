import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/composition/windows_platform_security_bridge.dart';
import 'package:personal_os_device_security/device_security.dart';

const _windowsChannel = MethodChannel('personal_os/internal/windows_vault');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowsChannel, null);
  });

  test('default Windows binding uses the frozen private channel ABI', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowsChannel, (call) async {
      expect(call.method, 'inspectCapabilities');
      return <String, Object?>{
        'protectionLevel': 'tpm',
        'userAuthenticationAvailable': true,
        'deviceCredentialAvailable': true,
        'nonExportableKeys': true,
        'atomicDeviceRevocation': false,
      };
    });

    final bridge = WindowsPlatformSecurityBridge();
    final capabilities = await bridge.inspectCapabilities();

    expect(capabilities.protectionLevel, HardwareProtectionLevel.tpm);
    expect(capabilities.userAuthenticationAvailable, isTrue);
    expect(capabilities.nonExportableKeys, isTrue);
  });

  test('missing Windows native channel fails closed', () async {
    final bridge = WindowsPlatformSecurityBridge();

    await expectLater(
      bridge.inspectCapabilities(),
      throwsA(
        isA<PlatformSecurityFailure>().having(
          (error) => error.code,
          'code',
          PlatformSecurityFailureCode.unavailable,
        ),
      ),
    );
  });
}
