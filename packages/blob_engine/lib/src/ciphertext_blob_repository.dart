import 'dart:typed_data';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_security_api/security_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

/// Storage metadata safe to persist beside ciphertext.
///
/// It contains no plaintext path, content hash, platform URI, or key bytes.
final class CiphertextBlobMetadata {
  CiphertextBlobMetadata({
    required this.key,
    required this.mediaType,
    required this.consentRef,
    required this.plaintextLength,
    required this.sensitivity,
    required this.createdAt,
  }) {
    validateBlobPersistenceSensitivity(sensitivity);
    if (key.purpose != KeyPurpose.blob) {
      throw ArgumentError.value(key.purpose, 'key', 'must be a blob key');
    }
    if (mediaType.trim().isEmpty) {
      throw ArgumentError.value(mediaType, 'mediaType', 'must not be blank');
    }
    if (consentRef.trim().isEmpty || consentRef != consentRef.trim()) {
      throw ArgumentError.value(consentRef, 'consentRef', 'must be non-blank');
    }
    if (mediaType != mediaType.trim() ||
        mediaType.length > 127 ||
        !RegExp(r'^[A-Za-z0-9!#\$&^_.+\-]+/[A-Za-z0-9!#\$&^_.+\-]+$')
            .hasMatch(mediaType)) {
      throw ArgumentError.value(
        mediaType,
        'mediaType',
        'must be a single bounded type/subtype token',
      );
    }
    if (plaintextLength < 0) {
      throw ArgumentError.value(
        plaintextLength,
        'plaintextLength',
        'must be >= 0',
      );
    }
    if (!createdAt.isUtc) {
      throw ArgumentError.value(createdAt, 'createdAt', 'must be UTC');
    }
  }

  final KeyHandle key;
  final String mediaType;
  final String consentRef;
  final int plaintextLength;
  final Sensitivity sensitivity;
  final DateTime createdAt;
}

final class CiphertextBlobRead {
  CiphertextBlobRead({required this.metadata, required this.ciphertext}) {
    CiphertextBlobMetadata(
      key: metadata.key,
      mediaType: metadata.mediaType,
      consentRef: metadata.consentRef,
      plaintextLength: metadata.plaintextLength,
      sensitivity: metadata.sensitivity,
      createdAt: metadata.createdAt,
    );
  }

  final CiphertextBlobMetadata metadata;
  final Stream<Uint8List> ciphertext;
}

/// Transactional ciphertext-only repository.
abstract interface class CiphertextBlobRepository {
  /// Creates an uncommitted, non-addressable write.
  Future<CiphertextBlobWrite> beginWrite({required BlobAccessContext access});

  /// Returns only committed ciphertext. Missing/aborted writes return null.
  Future<CiphertextBlobRead?> open(
    BlobRef ref, {
    required BlobAccessContext access,
  });

  Future<CiphertextBlobMetadata?> metadata(
    BlobRef ref, {
    required BlobAccessContext access,
  });

  /// Idempotently removes committed ciphertext and adapter-owned partials.
  Future<bool> deleteCiphertext(
    BlobRef ref, {
    required BlobAccessContext access,
  });
}

abstract interface class CiphertextBlobWrite {
  BlobRef get ref;

  /// Consumes ciphertext chunks without making them addressable.
  Future<void> write(Stream<Uint8List> ciphertext);

  /// Atomically makes the completed ciphertext addressable.
  Future<void> commit(CiphertextBlobMetadata metadata);

  /// Idempotently erases every partial owned by this write.
  Future<void> abort();
}
