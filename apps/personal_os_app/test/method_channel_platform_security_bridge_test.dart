import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/composition/android_platform_security_bridge.dart';
import 'package:personal_os_app/src/composition/method_channel_platform_security_bridge.dart';
import 'package:personal_os_device_security/device_security.dart';
import 'package:personal_os_security_api/security_api.dart';

const _channel = MethodChannel('test/personal_os/platform_security');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('decodes capabilities and forwards bounded authentication input', () async {
    final expiresAt = DateTime.utc(2026, 9, 14, 12, 30);
    _respond((call) async {
      switch (call.method) {
        case 'inspectCapabilities':
          return <String, Object?>{
            'protectionLevel': 'tpm',
            'userAuthenticationAvailable': true,
            'deviceCredentialAvailable': true,
            'nonExportableKeys': true,
            'atomicDeviceRevocation': false,
          };
        case 'authenticate':
          final arguments = _arguments(call);
          expect(
            arguments.keys.toSet(),
            <String>{'reason', 'allowDeviceCredential'},
          );
          expect(arguments['reason'], 'Open Personal OS vault');
          expect(arguments['allowDeviceCredential'], isTrue);
          return <String, Object?>{
            'id': 'opaque-auth-ticket',
            'expiresAt': expiresAt.millisecondsSinceEpoch,
          };
      }
      fail('unexpected method ${call.method}');
    });

    final bridge = MethodChannelPlatformSecurityBridge(channel: _channel);
    final capabilities = await bridge.inspectCapabilities();
    final ticket = await bridge.authenticate(
      PlatformAuthenticationRequest(
        reason: 'Open Personal OS vault',
        allowDeviceCredential: true,
      ),
    );

    expect(capabilities.protectionLevel, HardwareProtectionLevel.tpm);
    expect(capabilities.userAuthenticationAvailable, isTrue);
    expect(capabilities.deviceCredentialAvailable, isTrue);
    expect(capabilities.nonExportableKeys, isTrue);
    expect(capabilities.atomicDeviceRevocation, isFalse);
    expect(ticket.id, 'opaque-auth-ticket');
    expect(ticket.expiresAt, expiresAt);
  });

  test('encodes opaque key references and copies wrapped ciphertext', () async {
    final key = PlatformKeyReference(
      id: 'vault-key-ref',
      purpose: KeyPurpose.vaultMaster,
      version: 2,
    );
    final wrappingKey = PlatformKeyReference(
      id: 'wrapping-key-ref',
      purpose: KeyPurpose.deviceWrapping,
      version: 4,
    );

    _respond((call) async {
      expect(call.method, 'wrapKey');
      final arguments = _arguments(call);
      expect(arguments['authenticationTicketId'], 'opaque-auth-ticket');
      expect(
        arguments['key'],
        <String, Object?>{
          'id': 'vault-key-ref',
          'purpose': 'vaultMaster',
          'version': 2,
        },
      );
      expect(
        arguments['wrappingKey'],
        <String, Object?>{
          'id': 'wrapping-key-ref',
          'purpose': 'deviceWrapping',
          'version': 4,
        },
      );
      return <String, Object?>{
        'keyId': 'vault-key-ref',
        'purpose': 'vaultMaster',
        'version': 2,
        'ciphertext': <int>[11, 22, 33, 44],
      };
    });

    final bridge = MethodChannelPlatformSecurityBridge(channel: _channel);
    final wrapped = await bridge.wrapKey(
      key: key,
      wrappingKey: wrappingKey,
      authenticationTicketId: 'opaque-auth-ticket',
    );

    expect(wrapped.keyId, 'vault-key-ref');
    expect(wrapped.purpose, KeyPurpose.vaultMaster);
    expect(wrapped.version, 2);
    expect(wrapped.ciphertext, orderedEquals(<int>[11, 22, 33, 44]));

    final firstCopy = wrapped.ciphertext;
    firstCopy[0] = 99;
    expect(wrapped.ciphertext.first, 11);
  });

  test('maps allowlisted native errors and redacts native details', () async {
    _respond((call) async {
      throw PlatformException(
        code: call.method == 'authenticate'
            ? 'security.unlock_denied'
            : 'security.vault_session_invalid',
        message: 'alias=production-key path=C:/private/vault.db',
        details: <String, Object?>{'secret': 'must-not-cross'},
      );
    });

    final bridge = MethodChannelPlatformSecurityBridge(channel: _channel);
    try {
      await bridge.authenticate(
        PlatformAuthenticationRequest(
          reason: 'Open vault',
          allowDeviceCredential: false,
        ),
      );
      fail('expected platform security failure');
    } on PlatformSecurityFailure catch (error) {
      expect(error.code, PlatformSecurityFailureCode.denied);
      expect(error.toString(), isNot(contains('production-key')));
      expect(error.toString(), isNot(contains('C:/private')));
      expect(error.toString(), isNot(contains('must-not-cross')));
    }

    await expectLater(
      bridge.closeVault(session: PlatformVaultSession(id: 'session-1')),
      throwsA(_failure(PlatformSecurityFailureCode.vaultSessionInvalid)),
    );
  });

  test('unknown native errors and malformed payloads fail closed', () async {
    _respond((call) async {
      if (call.method == 'inspectCapabilities') {
        throw PlatformException(
          code: 'native.secret.failure',
          message: 'credential=must-not-cross',
        );
      }
      return <String, Object?>{
        'id': '',
        'expiresAt': 'not-an-epoch',
      };
    });

    final bridge = MethodChannelPlatformSecurityBridge(channel: _channel);
    await expectLater(
      bridge.inspectCapabilities(),
      throwsA(_failure(PlatformSecurityFailureCode.unavailable)),
    );
    await expectLater(
      bridge.authenticate(
        PlatformAuthenticationRequest(
          reason: 'Open vault',
          allowDeviceCredential: false,
        ),
      ),
      throwsA(_failure(PlatformSecurityFailureCode.unavailable)),
    );
  });

  test('Android binding delegates through the shared codec', () async {
    _respond((call) async {
      expect(call.method, 'inspectCapabilities');
      return <String, Object?>{
        'protectionLevel': 'strongBox',
        'userAuthenticationAvailable': true,
        'deviceCredentialAvailable': true,
        'nonExportableKeys': true,
        'atomicDeviceRevocation': true,
      };
    });

    final bridge = AndroidPlatformSecurityBridge(channel: _channel);
    final capabilities = await bridge.inspectCapabilities();

    expect(capabilities.protectionLevel, HardwareProtectionLevel.strongBox);
    expect(capabilities.atomicDeviceRevocation, isTrue);
  });
}

void _respond(Future<Object?> Function(MethodCall) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

Map<String, Object?> _arguments(MethodCall call) {
  final value = call.arguments;
  if (value is! Map) fail('expected map arguments for ${call.method}');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

Matcher _failure(PlatformSecurityFailureCode code) =>
    isA<PlatformSecurityFailure>().having(
      (error) => error.code,
      'code',
      code,
    );
