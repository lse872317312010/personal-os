import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/screens/capture_screen.dart';

void main() {
  test('ambiguous provider failures do not promise the photo was not sent', () {
    for (final code in <String>[
      'model.adapter_unavailable',
      'model.invalid_response',
    ]) {
      final message = captureErrorMessage(code);
      expect(message, contains('照片可能已发送'));
      expect(message, isNot(contains('照片未发送')));
      expect(message, isNot(contains('尚未配置')));
    }
  });

  test('missing per-send confirmation retains the pre-transmission guarantee',
      () {
    expect(
      captureErrorMessage('external_transmission_confirmation_required'),
      contains('照片未读取也未发送'),
    );
  });
}
