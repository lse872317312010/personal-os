import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  group('BlobRef', () {
    test('is value comparable but redacted when logged', () {
      final a = BlobRef('opaque-123');
      final b = BlobRef('opaque-123');

      expect(a, b);
      expect(a.encode(), 'opaque-123');
      expect(a.toString(), 'BlobRef(<redacted>)');
      expect(a.toString(), isNot(contains('opaque-123')));
    });

    test('rejects blank tokens', () {
      expect(() => BlobRef('  '), throwsArgumentError);
    });
  });

  group('BlobAccessContext', () {
    test('contains audit facts but no D4 authority', () {
      final access = BlobAccessContext(
        actorRef: 'user:owner',
        purpose: 'appearance-analysis',
        consentRef: 'consent:1',
      );

      expect(access.actorRef, 'user:owner');
      expect(access.purpose, 'appearance-analysis');
      expect(access.consentRef, 'consent:1');
    });

    test('rejects blank audit fields', () {
      expect(
        () => BlobAccessContext(
          actorRef: 'user:owner',
          purpose: ' ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('D4 persistence invariant', () {
    test('D4 is always rejected with the stable error code', () {
      expect(
        () => validateBlobPersistenceSensitivity(Sensitivity.d4),
        throwsA(
          isA<BlobAccessDenied>().having(
            (error) => error.code,
            'code',
            'D4_PERSISTENCE_FORBIDDEN',
          ),
        ),
      );
    });

    test('all persistable sensitivity levels pass the same guard', () {
      for (final sensitivity in Sensitivity.values.where(
        (value) => value != Sensitivity.d4,
      )) {
        expect(
          () => validateBlobPersistenceSensitivity(sensitivity),
          returnsNormally,
        );
      }
    });

    test('D4 metadata cannot be represented as persisted state', () {
      expect(
        () => BlobMetadata(
          ref: BlobRef('opaque'),
          mediaType: 'application/octet-stream',
          byteLength: 0,
          sensitivity: Sensitivity.d4,
          createdAt: DateTime.utc(2026, 8, 20),
        ),
        throwsA(isA<BlobAccessDenied>()),
      );
    });
  });

  group('safe metadata and ranges', () {
    test('metadata exposes only logical fields', () {
      final metadata = BlobMetadata(
        ref: BlobRef('opaque'),
        mediaType: 'image/jpeg',
        byteLength: 42,
        sensitivity: Sensitivity.d3,
        createdAt: DateTime.utc(2026, 8, 20),
      );

      expect(metadata.byteLength, 42);
      expect(metadata.sensitivity, Sensitivity.d3);
    });

    test('range is half-open and validated', () {
      expect(BlobByteRange(start: 0, endExclusive: 1).endExclusive, 1);
      expect(
        () => BlobByteRange(start: 1, endExclusive: 1),
        throwsArgumentError,
      );
      expect(() => BlobByteRange(start: -1), throwsArgumentError);
    });
  });
}
