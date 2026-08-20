import 'dart:typed_data';

import 'secure_unlock_port.dart';

enum KeyPurpose {
  deviceIdentity,
  deviceWrapping,
  vaultMaster,
  blob,
  accountEpoch,
  recovery,
}

/// Opaque reference to non-exportable key material owned by an adapter.
final class KeyHandle {
  KeyHandle({required String id, required this.purpose, required this.version})
      : id = _nonBlank(id, 'id') {
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'must be >= 1');
    }
  }

  final String id;
  final KeyPurpose purpose;
  final int version;
}

/// Encrypted key envelope. [ciphertext] must never contain plaintext material.
final class WrappedKey {
  WrappedKey({
    required String keyId,
    required this.keyPurpose,
    required this.keyVersion,
    required Uint8List ciphertext,
  })  : keyId = _nonBlank(keyId, 'keyId'),
        _ciphertext = Uint8List.fromList(ciphertext) {
    if (keyVersion < 1) {
      throw ArgumentError.value(keyVersion, 'keyVersion', 'must be >= 1');
    }
    if (ciphertext.isEmpty) {
      throw ArgumentError.value(ciphertext, 'ciphertext', 'must not be empty');
    }
  }

  final String keyId;
  final KeyPurpose keyPurpose;
  final int keyVersion;
  final Uint8List _ciphertext;

  /// Returns a defensive copy of the encrypted envelope.
  Uint8List get ciphertext => Uint8List.fromList(_ciphertext);
}

final class EpochRotation {
  const EpochRotation({required this.previous, required this.current});

  final KeyHandle previous;
  final KeyHandle current;
}

/// Cryptographic capability boundary. Implementations own all key bytes.
///
/// Deliberately absent: any `export`, `bytes`, or plaintext-key method.
abstract interface class KeyProvider {
  Future<KeyHandle> createKey({
    required KeyPurpose purpose,
    required UnlockGrant grant,
  });

  Future<WrappedKey> wrapKey({
    required KeyHandle key,
    required KeyHandle wrappingKey,
    required UnlockGrant grant,
  });

  /// Imports the envelope into protected storage and returns only a handle.
  Future<KeyHandle> unwrapKey({
    required WrappedKey wrappedKey,
    required KeyHandle wrappingKey,
    required UnlockGrant grant,
  });

  Future<EpochRotation> rotateAccountEpoch({
    required KeyHandle currentEpoch,
    required UnlockGrant grant,
  });

  /// Revocation must rotate the account epoch before returning successfully.
  Future<EpochRotation> revokeDevice({
    required String deviceId,
    required KeyHandle currentEpoch,
    required UnlockGrant grant,
  });

  /// Fails closed for a revoked device when encrypting future data.
  Future<void> authorizeNewData({
    required String deviceId,
    required KeyHandle epochKey,
  });

  Future<void> destroyKey({
    required KeyHandle key,
    required UnlockGrant grant,
  });
}

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}
