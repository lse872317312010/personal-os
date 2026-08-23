import 'package:personal_os_security_api/security_api.dart';

import 'platform_security_bridge.dart';
import 'safe_security_log.dart';

final class DeviceSecureUnlockAdapter implements SecureUnlockPort {
  DeviceSecureUnlockAdapter(this._bridge, {SafeSecurityLogSink? log})
      : _log = log ?? const NoopSafeSecurityLogSink();

  final PlatformSecurityBridge _bridge;
  final SafeSecurityLogSink _log;

  Future<DeviceSecurityCapabilities> inspectCapabilities() async {
    try {
      final value = await _bridge.inspectCapabilities();
      _success(SecurityOperation.capabilities);
      return value;
    } on PlatformSecurityFailure catch (error) {
      _failure(SecurityOperation.capabilities, error);
      throw _mapFailure(error);
    } catch (_) {
      const mapped = SecurityException(SecurityErrorCode.providerUnavailable);
      _stableFailure(SecurityOperation.capabilities, mapped.code);
      throw mapped;
    }
  }

  @override
  Future<UnlockGrant> requestUnlock(UnlockRequest request) async {
    try {
      final ticket = await _bridge.authenticate(PlatformAuthenticationRequest(
        reason: request.reason,
        allowDeviceCredential: request.allowDeviceCredential,
      ));
      final grant =
          UnlockGrant.opaque(id: ticket.id, expiresAt: ticket.expiresAt);
      _success(SecurityOperation.authenticate);
      return grant;
    } on PlatformSecurityFailure catch (error) {
      _failure(SecurityOperation.authenticate, error);
      throw _mapFailure(error);
    } catch (_) {
      const mapped = SecurityException(SecurityErrorCode.unlockUnavailable);
      _stableFailure(SecurityOperation.authenticate, mapped.code);
      throw mapped;
    }
  }

  void _success(SecurityOperation operation) => _log.record(SafeSecurityEvent(
        operation: operation,
        outcome: SecurityOperationOutcome.succeeded,
      ));

  void _failure(SecurityOperation operation, PlatformSecurityFailure error) =>
      _stableFailure(operation, _mapFailure(error).code);

  void _stableFailure(
    SecurityOperation operation,
    SecurityErrorCode code,
  ) =>
      _log.record(SafeSecurityEvent(
        operation: operation,
        outcome: SecurityOperationOutcome.failed,
        errorCode: code.wireValue,
      ));
}

SecurityException mapPlatformSecurityFailure(PlatformSecurityFailure failure) =>
    _mapFailure(failure);

SecurityException _mapFailure(PlatformSecurityFailure failure) =>
    SecurityException(
      switch (failure.code) {
        PlatformSecurityFailureCode.cancelled =>
          SecurityErrorCode.unlockCancelled,
        PlatformSecurityFailureCode.denied => SecurityErrorCode.unlockDenied,
        PlatformSecurityFailureCode.authenticationUnavailable =>
          SecurityErrorCode.unlockUnavailable,
        PlatformSecurityFailureCode.authenticationExpired =>
          SecurityErrorCode.unlockExpired,
        PlatformSecurityFailureCode.keyNotFound =>
          SecurityErrorCode.keyNotFound,
        PlatformSecurityFailureCode.purposeMismatch =>
          SecurityErrorCode.keyPurposeMismatch,
        PlatformSecurityFailureCode.keyDestroyed =>
          SecurityErrorCode.keyDestroyed,
        PlatformSecurityFailureCode.invalidEnvelope =>
          SecurityErrorCode.wrappedKeyInvalid,
        PlatformSecurityFailureCode.rotationConflict =>
          SecurityErrorCode.rotationConflict,
        PlatformSecurityFailureCode.deviceRevoked =>
          SecurityErrorCode.deviceRevoked,
        PlatformSecurityFailureCode.unavailable =>
          SecurityErrorCode.providerUnavailable,
      },
    );
