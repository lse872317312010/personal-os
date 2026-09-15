import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/composition/method_channel_platform_security_bridge.dart';
import 'package:personal_os_app/src/composition/windows_platform_security_bridge.dart';
import 'package:personal_os_device_security/device_security.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('personal_os/test/security');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('personal_os/internal/windows_vault'),
      null,
    );
  });

  test('shared bridge decodes capabilities and authentication ticket', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'inspectCapabilities':
          return <String, Object?>{
            'protectionLevel': 'tpm',
            'userAuthenticationAvailable': true,
            'deviceCredentialAvailable': true,
            'nonExportableKeys': false,
            'atomicDeviceRevocation': false,
          };
        case 'authenticate':
          return <String, Object?>{
            'id': 'ticket-opaque-1',
            'expiresAt': 1893456000000,
          };
        default:
          throw PlatformException(code: 'security.provider_unavailable');
      }
    });

    final bridge = MethodChannelPlatformSecurityBridge(channel);
    final capabilities = await bridge.inspectCapabilities();
    expect(capabilities.protectionLevel, HardwareProtectionLevel.tpm);
    expect(capabilities.userAuthenticationAvailable, isTrue);
    expect(capabilities.deviceCredentialAvailable, isTrue);
    expect(capabilities.nonExportableKeys, isFalse);
    expect(capabilities.atomicDeviceRevocation, isFalse);

    final ticket = await bridge.authenticate(
      PlatformAuthenticationRequest(
        reason: 'Open Personal OS vault',
        allowDeviceCredential: false,
      ),
    );
    expect(ticket.id, 'ticket-opaque-1');
    expect(
      ticket.expiresAt,
      DateTime.fromMillisecondsSinceEpoch(1893456000000, isUtc: true),
    );

    expect(calls.map((call) => call.method), <String>[
      'inspectCapabilities',
      'authenticate',
    ]);
    expect(
      calls.last.arguments,
      <String, Object?>{
        'reason': 'Open Personal OS vault',
        'allowDeviceCredential': false,
      },
    );
  });

  test('platform exception text and details are redacted', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'security.unlock_denied',
        message: 'native secret message',
        details: <String, Object?>{'path': r'C:\private\vault.db'},
      );
    });

    final bridge = MethodChannelPlatformSecurityBridge(channel);
    Object? captured;
    try {
      await bridge.authenticate(
        PlatformAuthenticationRequest(
          reason: 'Open Personal OS vault',
          allowDeviceCredential: true,
        ),
      );
    } catch (error) {
      captured = error;
    }

    expect(captured, isA<PlatformSecurityFailure>());
    final failure = captured! as PlatformSecurityFailure;
    expect(failure.code, PlatformSecurityFailureCode.denied);
    expect(failure.toString(), isNot(contains('native secret message')));
    expect(failure.toString(), isNot(contains('vault.db')));
  });

  test('missing native handler fails closed as unavailable', () async {
    final bridge = MethodChannelPlatformSecurityBridge(channel);

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

  test('Windows wrapper selects the isolated windows vault channel', () async {
    const windowsChannel = MethodChannel('personal_os/internal/windows_vault');
    MethodCall? captured;
    messenger.setMockMethodCallHandler(windowsChannel, (call) async {
      captured = call;
      return <String, Object?>{
        'protectionLevel': 'unavailable',
        'userAuthenticationAvailable': false,
        'deviceCredentialAvailable': false,
        'nonExportableKeys': false,
        'atomicDeviceRevocation': false,
      };
    });

    final bridge = WindowsPlatformSecurityBridge();
    final capabilities = await bridge.inspectCapabilities();

    expect(captured?.method, 'inspectCapabilities');
    expect(capabilities.protectionLevel, HardwareProtectionLevel.unavailable);
    expect(capabilities.userAuthenticationAvailable, isFalse);
  });
}
