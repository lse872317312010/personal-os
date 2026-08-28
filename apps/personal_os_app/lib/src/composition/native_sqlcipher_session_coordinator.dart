import 'dart:async';

import 'package:personal_os_device_security/device_security.dart';
import 'package:personal_os_security_api/security_api.dart';

import 'native_sqlcipher_event_store.dart';

/// App-private lifecycle owner for the one native session shared by secure UI
/// unlock/close and [NativeSqlCipherEventStore].
abstract interface class SecureSessionCoordinator {
  set onSessionInvalidated(void Function(SecurityException error) handler);

  Future<OpaqueVaultSession> open({required UnlockGrant grant});

  Future<void> close(OpaqueVaultSession session);
}

final class NativeSqlCipherSessionCoordinator
    implements SecureSessionCoordinator {
  NativeSqlCipherSessionCoordinator({
    required PlatformSecurityBridge bridge,
    required NativeSqlCipherEventStore eventStore,
  })  : _bridge = bridge,
        _eventStore = eventStore {
    _eventStore.setSessionInvalidatedHandler(_handleSessionInvalidated);
  }

  final PlatformSecurityBridge _bridge;
  final NativeSqlCipherEventStore _eventStore;
  _CoordinatorSession? _active;
  void Function(SecurityException error)? _onSessionInvalidated;

  /// Called by [AppController] to clear its volatile protected state.
  @override
  set onSessionInvalidated(void Function(SecurityException error) handler) {
    _onSessionInvalidated = handler;
  }

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

  void _handleSessionInvalidated(SecurityException error) {
    final active = _active;
    if (active != null) {
      active._invalidate();
      _active = null;
      _eventStore.detachNativeSession(active.nativeSession);
      unawaited(_closeAfterInvalidation(active.nativeSession));
    }
    final handler = _onSessionInvalidated;
    if (handler == null) return;
    try {
      handler(error);
    } on Object {
      // Keep the native capability invalidated even if UI cleanup fails.
    }
  }

  Future<void> _closeAfterInvalidation(PlatformVaultSession session) async {
    try {
      await _bridge.closeVault(session: session);
    } on Object {
      // The session is already detached locally; never re-expose native detail.
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
