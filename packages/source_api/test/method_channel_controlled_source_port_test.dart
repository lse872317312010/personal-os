import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_source_api/source_api.dart';

const _channel = MethodChannel('test/personal_os/controlled_source');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('capabilities accepts only the exact boolean response', () async {
    _respond((call) async {
      expect(call.method, 'capabilities');
      return <String, Object?>{'photoPicker': true, 'camera': false};
    });

    final result =
        await MethodChannelControlledSourcePort(channel: _channel)
            .capabilities();

    expect(result.photoPicker, isTrue);
    expect(result.camera, isFalse);
  });

  test('capabilities rejects metadata or non-boolean fields', () async {
    _respond((call) async => <String, Object?>{
          'photoPicker': true,
          'camera': false,
          'provider': 'must-not-cross',
        });

    await expectLater(
      MethodChannelControlledSourcePort(channel: _channel).capabilities(),
      throwsA(_failure(ControlledSourceFailureCode.invalidResponse)),
    );
  });

  test('malformed source response never becomes a Dart handle', () async {
    _respond((call) async => <String, Object?>{
          'token': 'content://provider/private/photo',
        });

    await expectLater(
      MethodChannelControlledSourcePort(channel: _channel).pickPhoto(),
      throwsA(_failure(ControlledSourceFailureCode.invalidResponse)),
    );
  });

  test('channel errors map to stable redacted failures', () async {
    _respond((call) async {
      throw PlatformException(
        code: 'source.denied',
        message: 'provider=/private/photo raw native detail',
      );
    });

    try {
      await MethodChannelControlledSourcePort(channel: _channel).pickPhoto();
      fail('expected source failure');
    } on ControlledSourceException catch (error) {
      expect(error.code, ControlledSourceFailureCode.denied);
      expect(error.toString(), isNot(contains('provider=')));
      expect(error.toString(), isNot(contains('/private/photo')));
      expect(error.toString(), isNot(contains('raw native detail')));
    }
  });

  test('unknown channel errors fail closed as unavailable', () async {
    _respond((call) async {
      throw PlatformException(
        code: 'native.internal.secret',
        message: 'keyAlias=prod/path=/private/photo',
      );
    });

    await expectLater(
      MethodChannelControlledSourcePort(channel: _channel).pickPhoto(),
      throwsA(_failure(ControlledSourceFailureCode.unavailable)),
    );
  });

  test('release is idempotent and never sends a released token twice', () async {
    var releaseCalls = 0;
    _respond((call) async {
      if (call.method == 'pickPhoto') {
        return <String, Object?>{'token': 'opaque_token_123456'};
      }
      if (call.method == 'release') {
        releaseCalls++;
        expect(
          call.arguments,
          <String, Object?>{'token': 'opaque_token_123456'},
        );
        return null;
      }
      fail('unexpected method: ${call.method}');
    });

    final port = MethodChannelControlledSourcePort(channel: _channel);
    final token = await port.pickPhoto();
    await port.release(token);
    await port.release(token);

    expect(releaseCalls, 1);
  });

  test('expired release is terminal and safe to repeat', () async {
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

  test('release rejects a token not issued by this adapter', () async {
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
