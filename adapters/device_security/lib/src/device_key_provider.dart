import 'package:personal_os_security_api/security_api.dart';

import 'device_secure_unlock.dart';
import 'platform_security_bridge.dart';
import 'safe_security_log.dart';

final class DeviceKeyProviderAdapter implements KeyProvider {
  DeviceKeyProviderAdapter(this._bridge, {SafeSecurityLogSink? log})
      : _log = log ?? const NoopSafeSecurityLogSink();

  final PlatformSecurityBridge _bridge;
  final SafeSecurityLogSink _log;

  @override
  Future<KeyHandle> createKey(
          {required KeyPurpose purpose, required UnlockGrant grant}) =>
      _run(
          SecurityOperation.createKey,
          () async => _toHandle(await _bridge.createKey(
                purpose: purpose,
                authenticationTicketId: grant.id,
              )));

  @override
  Future<WrappedKey> wrapKey(
          {required KeyHandle key,
          required KeyHandle wrappingKey,
          required UnlockGrant grant}) =>
      _run(SecurityOperation.wrapKey, () async {
        final wrapped = await _bridge.wrapKey(
          key: _toReference(key),
          wrappingKey: _toReference(wrappingKey),
          authenticationTicketId: grant.id,
        );
        return WrappedKey(
          keyId: wrapped.keyId,
          keyPurpose: wrapped.purpose,
          keyVersion: wrapped.version,
          ciphertext: wrapped.ciphertext,
        );
      });

  @override
  Future<KeyHandle> unwrapKey(
          {required WrappedKey wrappedKey,
          required KeyHandle wrappingKey,
          required UnlockGrant grant}) =>
      _run(
          SecurityOperation.unwrapKey,
          () async => _toHandle(await _bridge.unwrapKey(
                wrappedKey: PlatformWrappedKey(
                  keyId: wrappedKey.keyId,
                  purpose: wrappedKey.keyPurpose,
                  version: wrappedKey.keyVersion,
                  ciphertext: wrappedKey.ciphertext,
                ),
                wrappingKey: _toReference(wrappingKey),
                authenticationTicketId: grant.id,
              )));

  @override
  Future<EpochRotation> rotateAccountEpoch(
          {required KeyHandle currentEpoch, required UnlockGrant grant}) =>
      _run(
          SecurityOperation.rotateEpoch,
          () async => _toRotation(await _bridge.rotateAccountEpoch(
                currentEpoch: _toReference(currentEpoch),
                authenticationTicketId: grant.id,
              )));

  @override
  Future<EpochRotation> revokeDevice(
          {required String deviceId,
          required KeyHandle currentEpoch,
          required UnlockGrant grant}) =>
      _run(
          SecurityOperation.revokeDevice,
          () async => _toRotation(await _bridge.revokeDeviceAndRotate(
                deviceId: deviceId,
                currentEpoch: _toReference(currentEpoch),
                authenticationTicketId: grant.id,
              )));

  @override
  Future<void> authorizeNewData(
          {required String deviceId, required KeyHandle epochKey}) =>
      _run(
          SecurityOperation.authorizeNewData,
          () => _bridge.authorizeNewData(
                deviceId: deviceId,
                epochKey: _toReference(epochKey),
              ));

  @override
  Future<void> destroyKey(
          {required KeyHandle key, required UnlockGrant grant}) =>
      _run(
          SecurityOperation.destroyKey,
          () => _bridge.destroyKey(
                key: _toReference(key),
                authenticationTicketId: grant.id,
              ));

  Future<T> _run<T>(
      SecurityOperation operation, Future<T> Function() action) async {
    try {
      final result = await action();
      _log.record(SafeSecurityEvent(
          operation: operation, outcome: SecurityOperationOutcome.succeeded));
      return result;
    } on PlatformSecurityFailure catch (error) {
      final mapped = mapPlatformSecurityFailure(error);
      _log.record(SafeSecurityEvent(
        operation: operation,
        outcome: SecurityOperationOutcome.failed,
        errorCode: mapped.code.wireValue,
      ));
      throw mapped;
    } catch (_) {
      const mapped = SecurityException(SecurityErrorCode.providerUnavailable);
      _log.record(SafeSecurityEvent(
        operation: operation,
        outcome: SecurityOperationOutcome.failed,
        errorCode: SecurityErrorCode.providerUnavailable.wireValue,
      ));
      throw mapped;
    }
  }
}

PlatformKeyReference _toReference(KeyHandle value) => PlatformKeyReference(
      id: value.id,
      purpose: value.purpose,
      version: value.version,
    );

KeyHandle _toHandle(PlatformKeyReference value) =>
    KeyHandle(id: value.id, purpose: value.purpose, version: value.version);

EpochRotation _toRotation(PlatformEpochRotation value) => EpochRotation(
      previous: _toHandle(value.previous),
      current: _toHandle(value.current),
    );
