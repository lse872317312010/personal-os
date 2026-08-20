import 'dart:async';

import 'package:personal_os_domain/domain.dart';

/// Streaming, opaque storage boundary for encrypted binary objects.
///
/// Implementations MUST apply [BlobAccessContext] before opening or mutating a
/// blob. D4 is never persistable: [put] MUST call
/// [validateBlobPersistenceSensitivity] before consuming [bytes] and reject D4
/// with [BlobAccessDenied.d4PersistenceForbidden]. There is no authorization
/// or adapter override for this invariant.
abstract interface class BlobStore {
  /// A failed operation must not leave an addressable partial blob.
  Future<BlobRef> put({
    required Stream<List<int>> bytes,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  });

  /// Opens a fresh, bounded-memory byte stream.
  Stream<List<int>> openRead(
    BlobRef ref, {
    required BlobAccessContext access,
    BlobByteRange? range,
  });

  /// Returns logical metadata only: never paths, hashes, keys, or platform URIs.
  Future<BlobMetadata> metadata(
    BlobRef ref, {
    required BlobAccessContext access,
  });

  /// Idempotently makes [ref] unreadable and erases adapter-owned partials.
  Future<BlobDeleteResult> delete(
    BlobRef ref, {
    required BlobAccessContext access,
  });
}

/// An opaque logical capability, not a path, URI, hash, or key identifier.
final class BlobRef {
  BlobRef(String token) : _token = _nonBlank(token, 'token');

  final String _token;

  /// Explicit persistence/wire encoding. Do not log this value.
  String encode() => _token;

  @override
  bool operator ==(Object other) => other is BlobRef && other._token == _token;

  @override
  int get hashCode => _token.hashCode;

  @override
  String toString() => 'BlobRef(<redacted>)';
}

/// Auditable context attached to every blob operation.
///
/// This type intentionally cannot express permission to persist D4.
final class BlobAccessContext {
  BlobAccessContext({
    required String actorRef,
    required String purpose,
    String? consentRef,
  })  : actorRef = _nonBlank(actorRef, 'actorRef'),
        purpose = _nonBlank(purpose, 'purpose'),
        consentRef = _optionalNonBlank(consentRef, 'consentRef');

  final String actorRef;
  final String purpose;
  final String? consentRef;
}

final class BlobByteRange {
  BlobByteRange({required this.start, this.endExclusive}) {
    if (start < 0) throw ArgumentError.value(start, 'start', 'must be >= 0');
    if (endExclusive != null && endExclusive! <= start) {
      throw ArgumentError.value(
        endExclusive,
        'endExclusive',
        'must be greater than start',
      );
    }
  }

  final int start;
  final int? endExclusive;
}

final class BlobMetadata {
  BlobMetadata({
    required this.ref,
    required String mediaType,
    required this.byteLength,
    required this.sensitivity,
    required this.createdAt,
  }) : mediaType = _nonBlank(mediaType, 'mediaType') {
    validateBlobPersistenceSensitivity(sensitivity);
    if (byteLength < 0) {
      throw ArgumentError.value(byteLength, 'byteLength', 'must be >= 0');
    }
  }

  final BlobRef ref;
  final String mediaType;
  final int byteLength;
  final Sensitivity sensitivity;
  final DateTime createdAt;
}

enum BlobDeleteResult { deleted, alreadyAbsent }

final class BlobAccessDenied implements Exception {
  const BlobAccessDenied({required this.code, required this.reason});

  static const d4PersistenceForbidden = BlobAccessDenied(
    code: 'D4_PERSISTENCE_FORBIDDEN',
    reason: 'D4 data must never be persisted by BlobStore',
  );

  final String code;
  final String reason;

  @override
  String toString() => 'BlobAccessDenied($code): $reason';
}

/// Mandatory first step of every [BlobStore.put] implementation.
///
/// This guard is deliberately outside policy/consent evaluation: no actor,
/// purpose, consent, or adapter configuration can permit D4 persistence.
void validateBlobPersistenceSensitivity(Sensitivity sensitivity) {
  if (sensitivity == Sensitivity.d4) {
    throw BlobAccessDenied.d4PersistenceForbidden;
  }
}

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}

String? _optionalNonBlank(String? value, String label) {
  if (value == null) return null;
  return _nonBlank(value, label);
}
