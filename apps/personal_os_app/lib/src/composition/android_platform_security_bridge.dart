import 'package:flutter/services.dart';
import 'package:personal_os_device_security/device_security.dart';
import 'package:personal_os_security_api/security_api.dart';

/// Flutter-side composition adapter for the private Android vault channel.
///
/// The adapter maps only allowlisted platform codes. It never forwards a
/// PlatformException message or details object to the domain boundary.
final class AndroidPlatformSecurityBridge implements PlatformSecurityBridge {
  AndroidPlatformSecurityBridge({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('personal_os/internal/android_vault');

  final MethodChannel _channel;

  @override
  Future<DeviceSecurityCapabilities> inspectCapabilities() async {
    final value = await _invokeMap('inspectCapabilities');
    return DeviceSecurityCapabilities(
      protectionLevel: _protectionLevel(value['protectionLevel']),
      userAuthenticationAvailable: _bool(value['userAuthenticationAvailable']),
      deviceCredentialAvailable: _bool(value['deviceCredentialAvailable']),
      nonExportableKeys: _bool(value['nonExportableKeys']),
      atomicDeviceRevocation: _bool(value['atomicDeviceRevocation']),
    );
  }

  @override
  Future<PlatformAuthenticationTicket> authenticate(
    PlatformAuthenticationRequest request,
  ) async {
    final value = await _invokeMap(
      'authenticate',
      <String, Object?>{
        'reason': request.reason,
        'allowDeviceCredential': request.allowDeviceCredential,
      },
    );
    return PlatformAuthenticationTicket(
      id: _string(value['id']),
      expiresAt: _time(value['expiresAt']),
    );
  }

  @override
  Future<PlatformVaultSession> openVault({
    required String authenticationTicketId,
    required DateTime ticketExpiresAt,
  }) async {
    final value = await _invokeMap(
      'openVault',
      <String, Object?>{
        'authenticationTicketId': authenticationTicketId,
        'ticketExpiresAt': ticketExpiresAt.toUtc().millisecondsSinceEpoch,
      },
    );
    return PlatformVaultSession(id: _string(value['id']));
  }

  @override
  Future<void> closeVault({required PlatformVaultSession session}) async {
    await _invoke(
      'closeVault',
      <String, Object?>{'sessionId': session.id},
    );
  }

  @override
  Future<PlatformKeyReference> createKey({
    required KeyPurpose purpose,
    required String authenticationTicketId,
  }) async {
    final value = await _invokeMap(
      'createKey',
      <String, Object?>{
        'purpose': purpose.name,
        'authenticationTicketId': authenticationTicketId,
      },
    );
    return _keyReference(value);
  }

  @override
  Future<PlatformWrappedKey> wrapKey({
    required PlatformKeyReference key,
    required PlatformKeyReference wrappingKey,
    required String authenticationTicketId,
  }) async {
    final value = await _invokeMap(
      'wrapKey',
      <String, Object?>{
        'key': _keyJson(key),
        'wrappingKey': _keyJson(wrappingKey),
        'authenticationTicketId': authenticationTicketId,
      },
    );
    return PlatformWrappedKey(
      keyId: _string(value['keyId']),
      purpose: _keyPurpose(value['purpose']),
      version: _int(value['version']),
      ciphertext: _bytes(value['ciphertext']),
    );
  }

  @override
  Future<PlatformKeyReference> unwrapKey({
    required PlatformWrappedKey wrappedKey,
    required PlatformKeyReference wrappingKey,
    required String authenticationTicketId,
  }) async {
    final value = await _invokeMap(
      'unwrapKey',
      <String, Object?>{
        'wrappedKey': <String, Object?>{
          'keyId': wrappedKey.keyId,
          'purpose': wrappedKey.purpose.name,
          'version': wrappedKey.version,
          'ciphertext': wrappedKey.ciphertext,
        },
        'wrappingKey': _keyJson(wrappingKey),
        'authenticationTicketId': authenticationTicketId,
      },
    );
    return _keyReference(value);
  }

  @override
  Future<PlatformEpochRotation> rotateAccountEpoch({
    required PlatformKeyReference currentEpoch,
    required String authenticationTicketId,
  }) async {
    final value = await _invokeMap(
      'rotateAccountEpoch',
      <String, Object?>{
        'currentEpoch': _keyJson(currentEpoch),
        'authenticationTicketId': authenticationTicketId,
      },
    );
    return _rotation(value);
  }

  @override
  Future<PlatformEpochRotation> revokeDeviceAndRotate({
    required String deviceId,
    required PlatformKeyReference currentEpoch,
    required String authenticationTicketId,
  }) async {
    final value = await _invokeMap(
      'revokeDeviceAndRotate',
      <String, Object?>{
        'deviceId': deviceId,
        'currentEpoch': _keyJson(currentEpoch),
        'authenticationTicketId': authenticationTicketId,
      },
    );
    return _rotation(value);
  }

  @override
  Future<void> authorizeNewData({
    required String deviceId,
    required PlatformKeyReference epochKey,
  }) async {
    await _invoke(
      'authorizeNewData',
      <String, Object?>{
        'deviceId': deviceId,
        'epochKey': _keyJson(epochKey),
      },
    );
  }

  @override
  Future<void> destroyKey({
    required PlatformKeyReference key,
    required String authenticationTicketId,
  }) async {
    await _invoke(
      'destroyKey',
      <String, Object?>{
        'key': _keyJson(key),
        'authenticationTicketId': authenticationTicketId,
      },
    );
  }

  Future<Object?> _invoke(String method,
      [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      throw PlatformSecurityFailure(_failureCode(error.code));
    } on MissingPluginException {
      throw const PlatformSecurityFailure(
        PlatformSecurityFailureCode.unavailable,
      );
    } catch (_) {
      throw const PlatformSecurityFailure(
        PlatformSecurityFailureCode.unavailable,
      );
    }
  }

  Future<Map<String, Object?>> _invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final value = await _invoke(method, arguments);
    if (value is! Map) {
      throw const PlatformSecurityFailure(
        PlatformSecurityFailureCode.unavailable,
      );
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}

PlatformSecurityFailureCode _failureCode(String code) => switch (code) {
      'security.unlock_cancelled' => PlatformSecurityFailureCode.cancelled,
      'security.unlock_denied' => PlatformSecurityFailureCode.denied,
      'security.unlock_unavailable' =>
        PlatformSecurityFailureCode.authenticationUnavailable,
      'security.unlock_expired' =>
        PlatformSecurityFailureCode.authenticationExpired,
      'security.key_not_found' => PlatformSecurityFailureCode.keyNotFound,
      'security.key_purpose_mismatch' =>
        PlatformSecurityFailureCode.purposeMismatch,
      'security.key_destroyed' => PlatformSecurityFailureCode.keyDestroyed,
      'security.plaintext_key_export_forbidden' =>
        PlatformSecurityFailureCode.unavailable,
      'security.wrapped_key_invalid' =>
        PlatformSecurityFailureCode.invalidEnvelope,
      'security.rotation_conflict' =>
        PlatformSecurityFailureCode.rotationConflict,
      'security.device_revoked' => PlatformSecurityFailureCode.deviceRevoked,
      'security.vault_locked' => PlatformSecurityFailureCode.vaultLocked,
      'security.provider_unavailable' =>
        PlatformSecurityFailureCode.unavailable,
      _ => PlatformSecurityFailureCode.unavailable,
    };

HardwareProtectionLevel _protectionLevel(Object? value) => switch (value) {
      'software' => HardwareProtectionLevel.software,
      'trustedEnvironment' => HardwareProtectionLevel.trustedEnvironment,
      'strongBox' => HardwareProtectionLevel.strongBox,
      'secureEnclave' => HardwareProtectionLevel.secureEnclave,
      'tpm' => HardwareProtectionLevel.tpm,
      _ => HardwareProtectionLevel.unavailable,
    };

PlatformKeyReference _keyReference(Map<String, Object?> value) =>
    PlatformKeyReference(
      id: _string(value['id']),
      purpose: _keyPurpose(value['purpose']),
      version: _int(value['version']),
    );

PlatformEpochRotation _rotation(Map<String, Object?> value) =>
    PlatformEpochRotation(
      previous: _keyReference(_map(value['previous'])),
      current: _keyReference(_map(value['current'])),
    );

Map<String, Object?> _keyJson(PlatformKeyReference value) => <String, Object?>{
      'id': value.id,
      'purpose': value.purpose.name,
      'version': value.version,
    };

KeyPurpose _keyPurpose(Object? value) => KeyPurpose.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw const PlatformSecurityFailure(
        PlatformSecurityFailureCode.unavailable,
      ),
    );

Map<String, Object?> _map(Object? value) {
  if (value is! Map) {
    throw const PlatformSecurityFailure(
      PlatformSecurityFailureCode.unavailable,
    );
  }
  return value.map((key, value) => MapEntry(key.toString(), value));
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const PlatformSecurityFailure(
      PlatformSecurityFailureCode.unavailable,
    );
  }
  return value;
}

int _int(Object? value) {
  if (value is! int) {
    throw const PlatformSecurityFailure(
      PlatformSecurityFailureCode.unavailable,
    );
  }
  return value;
}

DateTime _time(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch(_int(value), isUtc: true);

bool _bool(Object? value) => value is bool && value;

Uint8List _bytes(Object? value) {
  if (value is Uint8List && value.isNotEmpty) return Uint8List.fromList(value);
  if (value is List && value.isNotEmpty && value.every((item) => item is int)) {
    return Uint8List.fromList(value.cast<int>());
  }
  throw const PlatformSecurityFailure(
    PlatformSecurityFailureCode.unavailable,
  );
}
