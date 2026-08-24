import 'dart:async';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_security_api/security_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

/// Stable, redacted failures raised by the encrypted-ingestion boundary.
final class BlobIngestionException implements Exception {
  const BlobIngestionException(this.code)
      : assert(
          code == 'consent_required' ||
              code == 'discard_failed' ||
              code == 'd4_persistence_forbidden' ||
              code == 'invalid_media_type' ||
              code == 'payload_too_large',
          'unstable blob ingestion error code',
        );

  final String code;

  @override
  String toString() => 'BlobIngestionException($code)';
}

/// Adapter-neutral ingress contract for encrypted blob persistence.
///
/// Implementations must validate the request before listening to [bytes], then
/// pass the bounded stream to a [BlobStore]. This contract has no path, URI,
/// raw-byte event, plaintext fallback, or in-memory fallback API.
abstract interface class BlobIngestionContract {
  Future<BlobRef> ingest({
    required Stream<List<int>> bytes,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  });
}

/// Optional compensation capability for implementations that support
/// transactional application workflows.
///
/// Kept separate from [BlobIngestionContract] so existing ingestion adapters
/// remain source-compatible. Implementations that persist addressable blobs
/// should implement this interface as well.
abstract interface class BlobIngestionRollback {
  Future<void> discard({
    required BlobRef ref,
    required BlobAccessContext access,
  });
}

/// The single external-input entry point for an encrypted [BlobStore].
final class EncryptedBlobIngestion
    implements BlobIngestionContract, BlobIngestionRollback {
  EncryptedBlobIngestion({required BlobStore store, required this.maxBytes})
      : _store = store {
    if (maxBytes <= 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be > 0');
    }
  }

  final BlobStore _store;
  final int maxBytes;

  @override
  Future<BlobRef> ingest({
    required Stream<List<int>> bytes,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  }) {
    _validateBeforeListening(mediaType, sensitivity, access);
    return _store.put(
      bytes: _bounded(bytes),
      mediaType: mediaType,
      sensitivity: sensitivity,
      access: access,
    );
  }

  @override
  Future<void> discard({
    required BlobRef ref,
    required BlobAccessContext access,
  }) async {
    try {
      await _store.delete(ref, access: access);
    } catch (_) {
      // Never expose adapter paths, SQL, key aliases, or raw exceptions at
      // this boundary. The composing use case retains the original failure.
      throw const BlobIngestionException('discard_failed');
    }
  }

  Stream<List<int>> _bounded(Stream<List<int>> source) async* {
    var total = 0;
    await for (final chunk in source) {
      if (chunk.length > maxBytes - total) {
        throw const BlobIngestionException('payload_too_large');
      }
      total += chunk.length;
      yield chunk;
    }
  }
}

void _validateBeforeListening(
  String mediaType,
  Sensitivity sensitivity,
  BlobAccessContext access,
) {
  if (access.consentRef == null) {
    throw const BlobIngestionException('consent_required');
  }
  try {
    validateBlobPersistenceSensitivity(sensitivity);
  } on BlobAccessDenied {
    throw const BlobIngestionException('d4_persistence_forbidden');
  }
  if (!_isValidMediaType(mediaType)) {
    throw const BlobIngestionException('invalid_media_type');
  }
}

bool _isValidMediaType(String mediaType) =>
    mediaType == mediaType.trim() &&
    mediaType.length <= 127 &&
    RegExp(r'^[A-Za-z0-9!#\$&^_.+\-]+/[A-Za-z0-9!#\$&^_.+\-]+$')
        .hasMatch(mediaType);
