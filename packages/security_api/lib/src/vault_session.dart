import 'secure_unlock_port.dart';
import 'security_error.dart';

enum VaultSessionState { locked, unlocked }

/// Controls access to vault capabilities without exposing vault key material.
abstract interface class VaultSession {
  VaultSessionState get state;

  bool get isUnlocked => state == VaultSessionState.unlocked;

  Future<void> unlock({required String reason});

  Future<void> lock();

  /// Returns the active capability or fails closed with [vaultLocked] or
  /// [unlockExpired].
  UnlockGrant requireGrant({DateTime? at});
}

/// Reusable state machine for adapters; stores only an authorization grant.
final class DefaultVaultSession implements VaultSession {
  DefaultVaultSession(this._unlockPort, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final SecureUnlockPort _unlockPort;
  final DateTime Function() _clock;
  UnlockGrant? _grant;

  @override
  VaultSessionState get state {
    final grant = _grant;
    return grant != null && grant.isValidAt(_clock())
        ? VaultSessionState.unlocked
        : VaultSessionState.locked;
  }

  @override
  bool get isUnlocked => state == VaultSessionState.unlocked;

  @override
  Future<void> unlock({required String reason}) async {
    // A failed re-authentication must not leave the previous capability
    // usable. This keeps the session fail-closed across retries.
    _grant = null;
    final grant = await _unlockPort.requestUnlock(UnlockRequest(reason: reason));
    if (!grant.isValidAt(_clock())) {
      _grant = null;
      throw const SecurityException(SecurityErrorCode.unlockExpired);
    }
    _grant = grant;
  }

  @override
  Future<void> lock() async => _grant = null;

  @override
  UnlockGrant requireGrant({DateTime? at}) {
    final grant = _grant;
    if (grant == null) {
      throw const SecurityException(SecurityErrorCode.vaultLocked);
    }
    if (!grant.isValidAt(at ?? _clock())) {
      _grant = null;
      throw const SecurityException(SecurityErrorCode.unlockExpired);
    }
    return grant;
  }
}
