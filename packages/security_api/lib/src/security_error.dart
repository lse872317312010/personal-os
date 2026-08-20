/// Stable, machine-readable failures at the security boundary.
enum SecurityErrorCode {
  vaultLocked('security.vault_locked'),
  unlockCancelled('security.unlock_cancelled'),
  unlockDenied('security.unlock_denied'),
  unlockUnavailable('security.unlock_unavailable'),
  unlockExpired('security.unlock_expired'),
  keyNotFound('security.key_not_found'),
  keyPurposeMismatch('security.key_purpose_mismatch'),
  keyDestroyed('security.key_destroyed'),
  wrappedKeyInvalid('security.wrapped_key_invalid'),
  rotationConflict('security.rotation_conflict'),
  deviceRevoked('security.device_revoked'),
  plaintextKeyExportForbidden('security.plaintext_key_export_forbidden'),
  providerUnavailable('security.provider_unavailable');

  const SecurityErrorCode(this.wireValue);

  final String wireValue;
}

final class SecurityException implements Exception {
  const SecurityException(this.code, {this.safeMessage});

  final SecurityErrorCode code;

  /// Must be safe for logs and must never contain key material.
  final String? safeMessage;

  @override
  String toString() => 'SecurityException(${code.wireValue})';
}
