import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/composition/method_channel_controlled_source_port.dart';
import 'package:personal_os_source_api/source_api.dart';

const _channel = MethodChannel('test/personal_os/controlled_source');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('accepts exact capabilities and bounded opaque token', () async {
    _respond((call) async {
      if (call.method == 'capabilities') {
        return <String, Object?>{'photoPicker': true, 'camera': false};
      }
      return <String, Object?>{'token': 'opaque_token_123456'};
    });

    final port = MethodChannelControlledSourcePort(channel: _channel);
    final capabilities = await port.capabilities();
    final token = await port.pickPhoto();

    expect(capabilities.photoPicker, isTrue);
    expect(capabilities.camera, isFalse);
    expect(token.value, 'opaque_token_123456');
  });

  test(
    'captures through the camera method without exposing metadata',
    () async {
      var calls = 0;
      _respond((call) async {
        expect(call.method, 'capturePhoto');
        calls++;
        return <String, Object?>{'token': 'opaque_camera_token_123'};
      });

      final port = MethodChannelControlledSourcePort(channel: _channel);
      final token = await port.capturePhoto();

      expect(token.value, 'opaque_camera_token_123');
      expect(calls, 1);
    },
  );

  test('rejects metadata and malformed tokens', () async {
    _respond((call) async {
      if (call.method == 'capabilities') {
        return <String, Object?>{
          'photoPicker': true,
          'camera': false,
          'provider': 'must-not-cross',
        };
      }
      return <String, Object?>{'token': 'content://provider/private/photo'};
    });

    final port = MethodChannelControlledSourcePort(channel: _channel);
    await expectLater(
      port.capabilities(),
      throwsA(_failure(ControlledSourceFailureCode.invalidResponse)),
    );
    await expectLater(
      port.pickPhoto(),
      throwsA(_failure(ControlledSourceFailureCode.invalidResponse)),
    );
  });

  test('maps allowlisted and unknown errors without leaking details', () async {
    _respond((call) async {
      throw PlatformException(
        code: call.method == 'pickPhoto' ? 'source.denied' : 'native.secret',
        message: 'keyAlias=prod path=/private/photo',
      );
    });

    final port = MethodChannelControlledSourcePort(channel: _channel);
    try {
      await port.pickPhoto();
      fail('expected source failure');
    } on ControlledSourceException catch (error) {
      expect(error.code, ControlledSourceFailureCode.denied);
      expect(error.toString(), isNot(contains('keyAlias')));
      expect(error.toString(), isNot(contains('/private/photo')));
    }

    await expectLater(
      port.capturePhoto(),
      throwsA(_failure(ControlledSourceFailureCode.unavailable)),
    );
  });

  test('release is idempotent and expired release is terminal', () async {
    var releaseCalls = 0;
    _respond((call) async {
      if (call.method == 'pickPhoto') {
        return <String, Object?>{'token': 'opaque_token_123456'};
      }
      releaseCalls++;
      throw PlatformException(code: 'source.expired');
    });

    final port = MethodChannelControlledSourcePort(channel: _channel);
    final token = await port.pickPhoto();
    await expectLater(
      port.release(token),
      throwsA(_failure(ControlledSourceFailureCode.sourceExpired)),
    );
    await port.release(token);
    expect(releaseCalls, 1);
  });

  test('release rejects an unissued valid-looking token', () async {
    var calls = 0;
    _respond((call) async {
      calls++;
      return null;
    });

    final port = MethodChannelControlledSourcePort(channel: _channel);
    await expectLater(
      port.release(OpaqueSourceToken('opaque_token_123456')),
      throwsA(_failure(ControlledSourceFailureCode.invalidResponse)),
    );
    expect(calls, 0);
  });
}

Matcher _failure(ControlledSourceFailureCode code) {
  return isA<ControlledSourceException>().having(
    (error) => error.code,
    'code',
    code,
  );
}

void _respond(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}
