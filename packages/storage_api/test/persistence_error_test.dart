import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  group('PersistenceException', () {
    test('wire values are stable and unique', () {
      final values =
          PersistenceErrorCode.values.map((code) => code.wireValue).toList();

      expect(values, hasLength(17));
      expect(values.toSet(), hasLength(values.length));
      expect(values, everyElement(startsWith('persistence.')));
    });

    test('evidence contains only allowlisted fields', () {
      const error = PersistenceException(
        PersistenceErrorCode.internalAdapterFailure,
      );

      expect(error.toEvidence(), {
        'code': 'persistence.internal_adapter_failure',
        'safe_message': 'The storage operation failed safely.',
      });
      expect(error.toEvidence().keys, unorderedEquals(['code', 'safe_message']));
    });

    test('string representation contains only the stable code', () {
      const error = PersistenceException(
        PersistenceErrorCode.vaultUnlockFailed,
      );

      expect(
        error.toString(),
        'PersistenceException(persistence.vault_unlock_failed)',
      );
      expect(error.toString(), isNot(contains('/')));
      expect(error.toString(), isNot(contains('Exception:')));
    });

    test('safe messages are fixed non-empty copy', () {
      for (final code in PersistenceErrorCode.values) {
        expect(code.safeMessage.trim(), isNotEmpty);
        expect(code.safeMessage, isNot(contains(r'\')));
        expect(code.safeMessage, isNot(contains('package:')));
        expect(code.safeMessage, isNot(contains('SELECT ')));
      }
    });
  });
}
