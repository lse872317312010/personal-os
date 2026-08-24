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
  const SecurityException(this.code);

  final SecurityErrorCode code;

  /// Stable text for user-facing or diagnostic surfaces.
  ///
  /// The caller cannot override this value, which prevents native exception
  /// text, paths, aliases, and other sensitive details from crossing the
  /// security boundary.
  String get safeMessage => _safeMessages[code]!;

  @override
  String toString() => 'SecurityException(${code.wireValue})';
}

const _safeMessages = <SecurityErrorCode, String>{
  SecurityErrorCode.vaultLocked: 'The vault is locked.',
  SecurityErrorCode.unlockCancelled: 'Unlock was cancelled.',
  SecurityErrorCode.unlockDenied: 'Unlock was denied.',
  SecurityErrorCode.unlockUnavailable: 'Unlock is unavailable.',
  SecurityErrorCode.unlockExpired: 'The unlock session expired.',
  SecurityErrorCode.keyNotFound: 'The requested key is unavailable.',
  SecurityErrorCode.keyPurposeMismatch:
      'The key cannot be used for this operation.',
  SecurityErrorCode.keyDestroyed: 'The requested key is no longer available.',
  SecurityErrorCode.wrappedKeyInvalid: 'The protected key envelope is invalid.',
  SecurityErrorCode.rotationConflict: 'Key rotation could not be completed.',
  SecurityErrorCode.deviceRevoked:
      'This device is not authorized for new data.',
  SecurityErrorCode.plaintextKeyExportForbidden:
      'Key material cannot be exported.',
  SecurityErrorCode.providerUnavailable:
      'Secure storage is temporarily unavailable.',
};
