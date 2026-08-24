/// Stable, adapter-neutral persistence failures exposed by storage ports.
enum PersistenceErrorCode {
  vaultLocked('persistence.vault_locked', 'The private vault is locked.'),
  vaultUnlockFailed(
    'persistence.vault_unlock_failed',
    'The private vault could not be unlocked.',
  ),
  vaultRekeyFailed(
    'persistence.vault_rekey_failed',
    'The private vault key could not be rotated.',
  ),
  vaultLifecycleInvalid(
    'persistence.vault_lifecycle_invalid',
    'The private vault is not ready for this operation.',
  ),
  eventAppendConflict(
    'persistence.event_append_conflict',
    'The event conflicts with existing data.',
  ),
  eventAppendRejected(
    'persistence.event_append_rejected',
    'The event could not be stored.',
  ),
  d4PersistenceForbidden(
    'persistence.d4_persistence_forbidden',
    'This content is not allowed in persistent storage.',
  ),
  sensitivityForbidden(
    'persistence.sensitivity_forbidden',
    'The content sensitivity is not allowed here.',
  ),
  forbiddenSecretField(
    'persistence.forbidden_secret_field',
    'Secret material is not allowed in this record.',
  ),
  keyNotFound(
    'persistence.key_not_found',
    'The required private key is unavailable.',
  ),
  keyPurposeMismatch(
    'persistence.key_purpose_mismatch',
    'The private key cannot be used for this operation.',
  ),
  keyDestroyed(
    'persistence.key_destroyed',
    'The private key is no longer available.',
  ),
  keyRotationConflict(
    'persistence.key_rotation_conflict',
    'Another key rotation is already in progress.',
  ),
  deviceRevoked(
    'persistence.device_revoked',
    'This device is no longer trusted.',
  ),
  providerUnavailable(
    'persistence.provider_unavailable',
    'Secure storage is temporarily unavailable.',
  ),
  invalidArgument(
    'persistence.invalid_argument',
    'The storage request is invalid.',
  ),
  internalAdapterFailure(
    'persistence.internal_adapter_failure',
    'The storage operation failed safely.',
  );

  const PersistenceErrorCode(this.wireValue, this.safeMessage);

  final String wireValue;

  /// Fixed, reviewed copy. It never includes adapter exception text.
  final String safeMessage;
}

/// The only persistence failure shape allowed to cross a storage Port.
final class PersistenceException implements Exception {
  const PersistenceException(this.code);

  final PersistenceErrorCode code;

  Map<String, String> toEvidence() => <String, String>{
        'code': code.wireValue,
        'safe_message': code.safeMessage,
      };

  @override
  String toString() => 'PersistenceException(' + code.wireValue + ')';
}
