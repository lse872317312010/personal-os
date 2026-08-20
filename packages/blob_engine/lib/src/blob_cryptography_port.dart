import 'dart:typed_data';

import 'package:personal_os_security_api/security_api.dart';

/// Production cryptography is deliberately outside this package.
///
/// Implementations must use authenticated encryption, keep key material in
/// protected storage, and return only an opaque [KeyHandle].
abstract interface class BlobCryptographyPort {
  Future<BlobSealSession> beginSeal();

  Stream<Uint8List> open({
    required KeyHandle key,
    required Stream<Uint8List> ciphertext,
  });

  /// Idempotently destroys [key]. A successful return means ciphertext using
  /// it can no longer be decrypted by this cryptography provider.
  Future<void> destroyKey(KeyHandle key);
}

/// One-use streaming encryption session with an already-created blob key.
abstract interface class BlobSealSession {
  KeyHandle get key;

  Stream<Uint8List> seal(Stream<Uint8List> plaintext);
}
