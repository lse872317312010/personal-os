import 'security_error.dart';

/// Platform-neutral request for OS-backed user presence/authentication.
final class UnlockRequest {
  UnlockRequest({required String reason, this.allowDeviceCredential = true})
      : reason = _nonBlank(reason, 'reason');

  final String reason;
  final bool allowDeviceCredential;
}

/// Opaque, short-lived authorization capability; it is not a key.
final class UnlockGrant {
  UnlockGrant._(this.id, this.expiresAt);

  factory UnlockGrant.opaque({
    required String id,
    required DateTime expiresAt,
  }) =>
      UnlockGrant._(_nonBlank(id, 'id'), expiresAt.toUtc());

  final String id;
  final DateTime expiresAt;

  bool isValidAt(DateTime instant) => instant.toUtc().isBefore(expiresAt);
}

/// Adapter boundary for Android Keystore, Apple Keychain, Windows Hello, etc.
abstract interface class SecureUnlockPort {
  /// Returns a capability or throws [SecurityException] with an unlock code.
  Future<UnlockGrant> requestUnlock(UnlockRequest request);
}

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}
