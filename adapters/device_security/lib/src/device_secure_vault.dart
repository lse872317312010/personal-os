import 'package:personal_os_security_api/security_api.dart';

import 'device_secure_unlock.dart';
import 'platform_security_bridge.dart';
import 'safe_security_log.dart';

/// Adapter implementation of the driver-neutral vault boundary.
///
/// This class only coordinates an opaque platform session. It does not
/// implement Android Keystore, SQLCipher, database migrations, or key storage.
final class DeviceSecureVaultPort implements SecureVaultPort {
  DeviceSecureVaultPort(
    this._bridge, {
    SafeSecurityLogSink? log,
    DateTime Function()? clock,
  })  : _log = log ?? const NoopSafeSecurityLogSink(),
        _clock = clock ?? DateTime.now;

  final PlatformSecurityBridge _bridge;
  final SafeSecurityLogSink _log;
  final DateTime Function() _clock;

  @override
  Future<OpaqueVaultSession> open({required UnlockGrant grant}) async {
    if (!grant.isValidAt(_clock())) {
      _recordFailure(SecurityOperation.openVault, SecurityErrorCode.unlockExpired);
      throw const SecurityException(SecurityErrorCode.unlockExpired);
    }

    try {
      final nativeSession = await _bridge.openVault(
        authenticationTicketId: grant.id,
        ticketExpiresAt: grant.expiresAt,
      );
      _recordSuccess(SecurityOperation.openVault);
      return _DeviceOpaqueVaultSession(this, nativeSession);
    } on PlatformSecurityFailure catch (error) {
      final mapped = mapPlatformSecurityFailure(error);
      _recordFailure(SecurityOperation.openVault, mapped.code);
      throw mapped;
    } catch (_) {
      const mapped = SecurityException(SecurityErrorCode.providerUnavailable);
      _recordFailure(SecurityOperation.openVault, mapped.code);
      throw mapped;
    }
  }

  @override
  Future<void> close(OpaqueVaultSession session) async {
    final value = session is _DeviceOpaqueVaultSession && session._owner == this
        ? session
        : null;
    if (value == null || !value.isActive) {
      _recordFailure(SecurityOperation.closeVault, SecurityErrorCode.vaultLocked);
      throw const SecurityException(SecurityErrorCode.vaultLocked);
    }

    // Invalidate before crossing the platform boundary. A close failure must
    // not leave a Dart capability usable or encourage a retry with stale state.
    value._invalidate();
    try {
      await _bridge.closeVault(session: value._nativeSession);
      _recordSuccess(SecurityOperation.closeVault);
    } on PlatformSecurityFailure catch (error) {
      final mapped = mapPlatformSecurityFailure(error);
      _recordFailure(SecurityOperation.closeVault, mapped.code);
      throw mapped;
    } catch (_) {
      const mapped = SecurityException(SecurityErrorCode.providerUnavailable);
      _recordFailure(SecurityOperation.closeVault, mapped.code);
      throw mapped;
    }
  }

  void _recordSuccess(SecurityOperation operation) => _log.record(SafeSecurityEvent(
        operation: operation,
        outcome: SecurityOperationOutcome.succeeded,
      ));

  void _recordFailure(SecurityOperation operation, SecurityErrorCode code) =>
      _log.record(SafeSecurityEvent(
        operation: operation,
        outcome: SecurityOperationOutcome.failed,
        errorCode: code.wireValue,
      ));
}

final class _DeviceOpaqueVaultSession implements OpaqueVaultSession {
  _DeviceOpaqueVaultSession(this._owner, this._nativeSession);

  final DeviceSecureVaultPort _owner;
  final PlatformVaultSession _nativeSession;
  bool _active = true;

  @override
  bool get isActive => _active;

  void _invalidate() => _active = false;
}

