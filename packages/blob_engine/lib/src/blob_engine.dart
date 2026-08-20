import 'dart:async';
import 'dart:typed_data';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_security_api/security_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'blob_cryptography_port.dart';
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
  const BlobEngineException(this.code);

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
      await write.commit(
        CiphertextBlobMetadata(
          key: seal.key,
          mediaType: mediaType,
          plaintextLength: plaintextLength,
          sensitivity: sensitivity,
          createdAt: _clock().toUtc(),
        ),
      );
      return write.ref;
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
    try {
      final record = await _repository.open(ref, access: access);
      if (record == null) throw const BlobEngineException('blob_not_found');
      final plaintext = _cryptography.open(
        key: record.metadata.key,
        ciphertext: record.ciphertext,
      );
      yield* _rangeAndZeroize(plaintext, range);
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
    try {
      final value = await _repository.metadata(ref, access: access);
      if (value == null) throw const BlobEngineException('blob_not_found');
      return BlobMetadata(
        ref: ref,
        mediaType: value.mediaType,
        byteLength: value.plaintextLength,
        sensitivity: value.sensitivity,
        createdAt: value.createdAt,
      );
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

    // Crypto-erasure is the security boundary. Never reverse this order.
    try {
      await _cryptography.destroyKey(value.key);
    } on Object {
      _safeLog?.call(BlobEngineEvent.deleteFailed);
      throw const BlobEngineException('delete_failed');
    }
    _safeLog?.call(BlobEngineEvent.keyDestroyed);
    try {
      await _repository.deleteCiphertext(ref, access: access);
    } on Object {
      _safeLog?.call(BlobEngineEvent.ciphertextCleanupFailed);
      throw const BlobEngineException('ciphertext_cleanup_failed');
    }
    return BlobDeleteResult.deleted;
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
  BlobByteRange? range,
) async* {
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
}

void _zeroize(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
