import 'package:personal_os_source_api/source_api.dart';
import 'package:test/test.dart';

void main() {
  test('tokens accept only opaque bounded identifiers', () {
    final token = OpaqueSourceToken('token_1234567890');
    expect(token.value, 'token_1234567890');
    expect(
      () => OpaqueSourceToken('content://provider/private/photo'),
      throwsFormatException,
    );
    expect(
      () => OpaqueSourceToken('/data/user/0/app/photo.jpg'),
      throwsFormatException,
    );
  });

  test('fake picker returns a token and never metadata', () async {
    final fake = FakeControlledSourcePort();
    final token = await fake.pickPhoto();
    expect(token, OpaqueSourceToken('fake_photo_token_01'));
    expect(token.value, isNot(contains('/')));
    expect(token.value, isNot(contains(':')));
  });

  test('camera is fail-closed when unavailable', () async {
    final fake = FakeControlledSourcePort();
    expect(
      () => fake.capturePhoto(),
      throwsA(
        isA<ControlledSourceException>().having(
          (error) => error.code,
          'code',
          ControlledSourceFailureCode.unavailable,
        ),
      ),
    );
  });

  test('configured native failure is stable and redacted', () async {
    final fake = FakeControlledSourcePort()
      ..nextFailure = ControlledSourceFailureCode.denied;
    try {
      await fake.pickPhoto();
      fail('expected failure');
    } on ControlledSourceException catch (error) {
      expect(
        error.toString(),
        'ControlledSourceException(ControlledSourceFailureCode.denied)',
      );
      expect(error.toString(), isNot(contains('content://')));
      expect(error.toString(), isNot(contains('/data/')));
    }
  });

  test('release accepts only the opaque token', () async {
    final fake = FakeControlledSourcePort();
    final token = await fake.pickPhoto();
    await fake.release(token);
    expect(fake.released, contains(token.value));
  });
}
