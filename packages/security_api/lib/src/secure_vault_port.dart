import 'secure_unlock_port.dart';
import 'security_error.dart';

/// A live vault capability owned by the secure-vault adapter.
///
/// This interface intentionally exposes no identifier, path, alias, database
/// connection, key lease, or byte representation. The object is only a
/// capability that can be passed back to the same [SecureVaultPort].
abstract interface class OpaqueVaultSession {
  bool get isActive;
}

/// Native boundary for opening the encrypted local vault.
///
/// Authentication is completed before [open] is called. A platform adapter
/// must validate the grant again inside its trusted boundary and keep all
/// database paths, key leases, and native handles private. This contract does
/// not claim that any platform implementation exists.
abstract interface class SecureVaultPort {
  /// Opens the vault using an already authenticated, short-lived capability.
  ///
  /// Implementations must fail closed with a [SecurityException] when the
  /// grant is expired, invalid, revoked, or otherwise unusable.
  Future<OpaqueVaultSession> open({required UnlockGrant grant});

  /// Closes and invalidates [session]. Reusing a closed session must fail.
  Future<void> close(OpaqueVaultSession session);
}
