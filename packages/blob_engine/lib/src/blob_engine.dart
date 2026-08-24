import 'dart:async';
import 'dart:typed_data';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_security_api/security_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'blob_cryptography_port.dart';
import 'blob_ingestion_contract.dart';
import 'ciphertext_blob_repository.dart';

enum BlobEngineEvent {
  putFailed,
  openFailed,
  metadataFailed,
  deleteFailed,
  keyDestroyed,
  ciphertextCleanupFailed,
}

typedef SafeBlobEngineLog = void Function(BlobEngineEvent event);

final class BlobEngineException implements Exception {
  const BlobEngineException(this.code)
      : assert(
          code == 'consent_required' ||
              code == 'put_failed' ||
              code == 'open_failed' ||
              code == 'metadata_failed' ||
              code == 'delete_failed' ||
              code == 'ciphertext_cleanup_failed' ||
              code == 'blob_not_found' ||
              code == 'invalid_blob_key' ||
              code == 'invalid_blob_metadata' ||
              code == 'plaintext_length_mismatch' ||
              code == 'consent_mismatch',
          'unstable blob error code',
        );

  final String code;

  @override
  String toString() => 'BlobEngineException($code)';
}

/// Trusted local blob orchestration.
///
/// Plaintext exists only in bounded owned chunks while crossing the
/// cryptography port. Logging is event-only by construction: references,
/// paths, hashes, key identifiers, and exception strings are never accepted.
final class EncryptedBlobEngine implements BlobStore {
  EncryptedBlobEngine({
    required CiphertextBlobRepository repository,
    required BlobCryptographyPort cryptography,
    SafeBlobEngineLog? safeLog,
    DateTime Function()? clock,
  })  : _repository = repository,
        _cryptography = cryptography,
        _safeLog = safeLog,
        _clock = clock ?? DateTime.now;

  final CiphertextBlobRepository _repository;
  final BlobCryptographyPort _cryptography;
  final SafeBlobEngineLog? _safeLog;
  final DateTime Function() _clock;
  final Set<BlobRef> _cryptoErased = <BlobRef>{};

  @override
  Future<BlobRef> put({
    required Stream<List<int>> bytes,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  }) async {
    // Mandatory before opening a transaction, creating a key, or listening to
    // the caller's stream. Consent cannot override this invariant.
    validateBlobPersistenceSensitivity(sensitivity);
    _requireConsent(access);

    CiphertextBlobWrite? write;
    BlobSealSession? seal;
    try {
      write = await _repository.beginWrite(access: access);
      seal = await _cryptography.beginSeal();
      if (seal.key.purpose != KeyPurpose.blob) {
        throw const BlobEngineException('invalid_blob_key');
      }

      var plaintextLength = 0;
      final plaintext = _ownedChunks(
        bytes,
        onLength: (length) => plaintextLength += length,
      );
      await write.write(seal.seal(plaintext));
      try {
        await write.commit(
          CiphertextBlobMetadata(
            key: seal.key,
            mediaType: mediaType,
            consentRef: access.consentRef!,
            plaintextLength: plaintextLength,
            sensitivity: sensitivity,
            createdAt: _clock().toUtc(),
          ),
        );
      } on ArgumentError {
        throw const BlobEngineException('invalid_blob_metadata');
      }
      return write.ref;
    } on BlobIngestionException {
      _safeLog?.call(BlobEngineEvent.putFailed);
      if (write != null) {
        try {
          await write.abort();
        } on Object {
          // The repository contract still requires partials to be inaccessible.
        }
      }
      if (seal != null) {
        try {
          await _cryptography.destroyKey(seal.key);
        } on Object {
          // Preserve the original failure; no committed ciphertext is readable.
        }
      }
      rethrow;
    } on Object {
      _safeLog?.call(BlobEngineEvent.putFailed);
      if (write != null) {
        try {
          await write.abort();
        } on Object {
          // The repository contract still requires partials to be inaccessible.
        }
      }
      if (seal != null) {
        try {
          await _cryptography.destroyKey(seal.key);
        } on Object {
          // Preserve the original failure; no committed ciphertext is readable.
        }
      }
      throw const BlobEngineException('put_failed');
    }
  }

  @override
  Stream<List<int>> openRead(
    BlobRef ref, {
    required BlobAccessContext access,
    BlobByteRange? range,
  }) async* {
    _requireConsent(access);
    try {
      final record = await _repository.open(ref, access: access);
      if (record == null) throw const BlobEngineException('blob_not_found');
      _validateRecord(record, access);
      final plaintext = _cryptography.open(
        key: record.metadata.key,
        ciphertext: record.ciphertext,
      );
      await for (final chunk in _rangeAndZeroize(
        plaintext,
        range,
        expectedLength: record.metadata.plaintextLength,
      )) {
        yield chunk;
      }
    } on BlobEngineException {
      _safeLog?.call(BlobEngineEvent.openFailed);
      rethrow;
    } on Object {
      _safeLog?.call(BlobEngineEvent.openFailed);
      throw const BlobEngineException('open_failed');
    }
  }

  @override
  Future<BlobMetadata> metadata(
    BlobRef ref, {
    required BlobAccessContext access,
  }) async {
    _requireConsent(access);
    try {
      final value = await _repository.metadata(ref, access: access);
      if (value == null) throw const BlobEngineException('blob_not_found');
      _validateMetadata(value, access);
      return BlobMetadata(
        ref: ref,
        mediaType: value.mediaType,
        byteLength: value.plaintextLength,
        sensitivity: value.sensitivity,
        createdAt: value.createdAt,
      );
    } on BlobEngineException {
      _safeLog?.call(BlobEngineEvent.metadataFailed);
      rethrow;
    } on Object {
      _safeLog?.call(BlobEngineEvent.metadataFailed);
      throw const BlobEngineException('metadata_failed');
    }
  }

  @override
  Future<BlobDeleteResult> delete(
    BlobRef ref, {
    required BlobAccessContext access,
  }) async {
    _requireConsent(access);
    CiphertextBlobMetadata? value;
    try {
      value = await _repository.metadata(ref, access: access);
    } on Object {
      _safeLog?.call(BlobEngineEvent.deleteFailed);
      throw const BlobEngineException('delete_failed');
    }
    if (value == null) {
      try {
        await _repository.deleteCiphertext(ref, access: access);
      } on Object {
        _safeLog?.call(BlobEngineEvent.ciphertextCleanupFailed);
        throw const BlobEngineException('ciphertext_cleanup_failed');
      }
      return BlobDeleteResult.alreadyAbsent;
    }
    try {
      _validateMetadata(value, access);
    } on BlobEngineException {
      _safeLog?.call(BlobEngineEvent.deleteFailed);
      rethrow;
    }

    // Crypto-erasure is the security boundary. Never reverse this order.
    if (!_cryptoErased.contains(ref)) {
      try {
        await _cryptography.destroyKey(value.key);
        _cryptoErased.add(ref);
      } on Object {
        _safeLog?.call(BlobEngineEvent.deleteFailed);
        throw const BlobEngineException('delete_failed');
      }
      _safeLog?.call(BlobEngineEvent.keyDestroyed);
    }
    try {
      await _repository.deleteCiphertext(ref, access: access);
    } on Object {
      _safeLog?.call(BlobEngineEvent.ciphertextCleanupFailed);
      throw const BlobEngineException('ciphertext_cleanup_failed');
    }
    _cryptoErased.remove(ref);
    return BlobDeleteResult.deleted;
  }
}

void _requireConsent(BlobAccessContext access) {
  if (access.consentRef == null) {
    throw const BlobEngineException('consent_required');
  }
}

void _validateMetadata(
  CiphertextBlobMetadata metadata,
  BlobAccessContext access,
) {
  try {
    CiphertextBlobMetadata(
      key: metadata.key,
      mediaType: metadata.mediaType,
      consentRef: metadata.consentRef,
      plaintextLength: metadata.plaintextLength,
      sensitivity: metadata.sensitivity,
      createdAt: metadata.createdAt,
    );
  } on ArgumentError {
    throw const BlobEngineException('invalid_blob_metadata');
  }
  if (metadata.consentRef != access.consentRef) {
    throw const BlobEngineException('consent_mismatch');
  }
}

void _validateRecord(CiphertextBlobRead record, BlobAccessContext access) {
  _validateMetadata(record.metadata, access);
  if (record.metadata.key.purpose != KeyPurpose.blob) {
    throw const BlobEngineException('invalid_blob_key');
  }
}

Stream<Uint8List> _ownedChunks(
  Stream<List<int>> source, {
  required void Function(int length) onLength,
}) async* {
  await for (final chunk in source) {
    final owned = Uint8List.fromList(chunk);
    onLength(owned.length);
    try {
      yield owned;
    } finally {
      _zeroize(owned);
    }
  }
}

Stream<Uint8List> _rangeAndZeroize(
  Stream<Uint8List> source,
  BlobByteRange? range, {
  required int expectedLength,
}) async* {
  var offset = 0;
  await for (final sourceChunk in source) {
    final owned = Uint8List.fromList(sourceChunk);
    try {
      final chunkStart = offset;
      final chunkEnd = offset + owned.length;
      offset = chunkEnd;
      final wantedStart = range?.start ?? 0;
      final wantedEnd = range?.endExclusive;
      final start = wantedStart > chunkStart ? wantedStart - chunkStart : 0;
      final end = wantedEnd == null || wantedEnd >= chunkEnd
          ? owned.length
          : wantedEnd - chunkStart;
      if (start < owned.length && end > start) {
        yield Uint8List.fromList(owned.sublist(start, end));
      }
      if (wantedEnd != null && chunkEnd >= wantedEnd) break;
    } finally {
      _zeroize(owned);
    }
  }
  if (range == null && offset != expectedLength) {
    throw const BlobEngineException('plaintext_length_mismatch');
  }
}

void _zeroize(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
