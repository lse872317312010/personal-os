import 'package:personal_os_device_security/device_security.dart';
import 'package:personal_os_security_api/security_api.dart';

import 'native_sqlcipher_event_store.dart';

/// App-private lifecycle owner for the one native session shared by secure UI
/// unlock/close and [NativeSqlCipherEventStore].
abstract interface class SecureSessionCoordinator {
  Future<OpaqueVaultSession> open({required UnlockGrant grant});

  Future<void> close(OpaqueVaultSession session);
}

final class NativeSqlCipherSessionCoordinator
    implements SecureSessionCoordinator {
  NativeSqlCipherSessionCoordinator({
    required PlatformSecurityBridge bridge,
    required NativeSqlCipherEventStore eventStore,
  })  : _bridge = bridge,
        _eventStore = eventStore;

  final PlatformSecurityBridge _bridge;
  final NativeSqlCipherEventStore _eventStore;
  _CoordinatorSession? _active;

  @override
  Future<OpaqueVaultSession> open({required UnlockGrant grant}) async {
    if (_active != null) {
      throw const SecurityException(SecurityErrorCode.vaultLocked);
    }
    try {
      final nativeSession = await _bridge.openVault(
        authenticationTicketId: grant.id,
        ticketExpiresAt: grant.expiresAt,
      );
      final session = _CoordinatorSession(nativeSession);
      try {
        _eventStore.attachNativeSession(nativeSession);
        _active = session;
        return session;
      } on Object {
        await _bridge.closeVault(session: nativeSession);
        rethrow;
      }
    } on PlatformSecurityFailure catch (error) {
      throw mapPlatformSecurityFailure(error);
    } on SecurityException {
      rethrow;
    } on Object {
      throw const SecurityException(SecurityErrorCode.providerUnavailable);
    }
  }

  @override
  Future<void> close(OpaqueVaultSession session) async {
    final active = _active;
    if (active == null || active != session || !active.isActive) {
      throw const SecurityException(SecurityErrorCode.vaultLocked);
    }
    active._invalidate();
    _active = null;
    _eventStore.detachNativeSession(active.nativeSession);
    try {
      await _bridge.closeVault(session: active.nativeSession);
    } on PlatformSecurityFailure catch (error) {
      throw mapPlatformSecurityFailure(error);
    } on Object {
      throw const SecurityException(SecurityErrorCode.providerUnavailable);
    }
  }
}

final class _CoordinatorSession implements OpaqueVaultSession {
  _CoordinatorSession(this.nativeSession);

  final PlatformVaultSession nativeSession;
  bool _active = true;

  @override
  bool get isActive => _active;

  void _invalidate() => _active = false;
}
