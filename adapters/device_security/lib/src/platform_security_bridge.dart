import 'dart:typed_data';

import 'package:personal_os_security_api/security_api.dart';

/// Protection level reported by the platform implementation at runtime.
///
/// A value is evidence supplied by the bridge, not an attestation made by this
/// Dart package. In particular, [strongBox] must not be inferred from Android
/// device model or OS version.
enum HardwareProtectionLevel { unavailable, software, trustedEnvironment, strongBox, secureEnclave, tpm }

final class DeviceSecurityCapabilities {
  const DeviceSecurityCapabilities({
    required this.protectionLevel,
    required this.userAuthenticationAvailable,
    required this.deviceCredentialAvailable,
    required this.nonExportableKeys,
    required this.atomicDeviceRevocation,
  });

  final HardwareProtectionLevel protectionLevel;
  final bool userAuthenticationAvailable;
  final bool deviceCredentialAvailable;
  final bool nonExportableKeys;
  final bool atomicDeviceRevocation;

  bool get isHardwareBacked => switch (protectionLevel) {
        HardwareProtectionLevel.trustedEnvironment ||
        HardwareProtectionLevel.strongBox ||
        HardwareProtectionLevel.secureEnclave ||
        HardwareProtectionLevel.tpm => true,
        _ => false,
      };
}

final class PlatformAuthenticationRequest {
  PlatformAuthenticationRequest({
    required String reason,
    required this.allowDeviceCredential,
  }) : reason = _nonBlank(reason, 'reason');

  final String reason;
  final bool allowDeviceCredential;
}

/// Opaque proof of recent platform authentication. It is never key material.
final class PlatformAuthenticationTicket {
  PlatformAuthenticationTicket({
    required String id,
    required DateTime expiresAt,
  })  : id = _nonBlank(id, 'id'),
        expiresAt = expiresAt.toUtc();

  final String id;
  final DateTime expiresAt;
}

/// Opaque native handle for an opened vault.
///
/// The adapter may pass this value back to the same bridge, but application
/// code must never receive it. Native implementations must not encode a path,
/// key, alias, or database connection in a value exposed outside this file's
/// adapter boundary.
final class PlatformVaultSession {
  PlatformVaultSession({required String id}) : id = _nonBlank(id, 'id');

  final String id;
}

final class PlatformKeyReference {
  PlatformKeyReference({
    required String id,
    required this.purpose,
    required this.version,
  }) : id = _nonBlank(id, 'id') {
    if (version < 1) throw ArgumentError.value(version, 'version', 'must be >= 1');
  }

  final String id;
  final KeyPurpose purpose;
  final int version;
}

final class PlatformWrappedKey {
  PlatformWrappedKey({
    required String keyId,
    required this.purpose,
    required this.version,
    required Uint8List ciphertext,
  })  : keyId = _nonBlank(keyId, 'keyId'),
        _ciphertext = Uint8List.fromList(ciphertext) {
    if (version < 1) throw ArgumentError.value(version, 'version', 'must be >= 1');
    if (ciphertext.isEmpty) {
      throw ArgumentError('ciphertext must not be empty');
    }
  }

  final String keyId;
  final KeyPurpose purpose;
  final int version;
  final Uint8List _ciphertext;

  Uint8List get ciphertext => Uint8List.fromList(_ciphertext);
}

final class PlatformEpochRotation {
  const PlatformEpochRotation({required this.previous, required this.current});

  final PlatformKeyReference previous;
  final PlatformKeyReference current;
}

/// Stable bridge failures; native exception text must not cross this boundary.
enum PlatformSecurityFailureCode {
  cancelled,
  denied,
  authenticationUnavailable,
  authenticationExpired,
  keyNotFound,
  purposeMismatch,
  keyDestroyed,
  invalidEnvelope,
  rotationConflict,
  deviceRevoked,
  vaultLocked,
  vaultSessionInvalid,
  unavailable,
}

final class PlatformSecurityFailure implements Exception {
  const PlatformSecurityFailure(this.code);

  final PlatformSecurityFailureCode code;

  @override
  String toString() => 'PlatformSecurityFailure(${code.name})';
}

/// Replaceable native boundary for Android, Apple and desktop implementations.
///
/// Implementations must keep key bytes inside platform-protected storage. There
/// is intentionally no plaintext import/export operation in this contract.
abstract interface class PlatformSecurityBridge {
  Future<DeviceSecurityCapabilities> inspectCapabilities();

  Future<PlatformAuthenticationTicket> authenticate(
    PlatformAuthenticationRequest request,
  );

  /// Opens the local vault using a short-lived authentication ticket.
  ///
  /// The native implementation must validate the ticket inside its trusted
  /// boundary and keep database keys, paths, and native handles private.
  Future<PlatformVaultSession> openVault({
    required String authenticationTicketId,
    required DateTime ticketExpiresAt,
  });

  /// Closes and invalidates a previously opened native vault session.
  Future<void> closeVault({required PlatformVaultSession session});

  Future<PlatformKeyReference> createKey({
    required KeyPurpose purpose,
    required String authenticationTicketId,
  });

  Future<PlatformWrappedKey> wrapKey({
    required PlatformKeyReference key,
    required PlatformKeyReference wrappingKey,
    required String authenticationTicketId,
  });

  Future<PlatformKeyReference> unwrapKey({
    required PlatformWrappedKey wrappedKey,
    required PlatformKeyReference wrappingKey,
    required String authenticationTicketId,
  });

  Future<PlatformEpochRotation> rotateAccountEpoch({
    required PlatformKeyReference currentEpoch,
    required String authenticationTicketId,
  });

  /// Must persist revocation and rotate the epoch atomically.
  Future<PlatformEpochRotation> revokeDeviceAndRotate({
    required String deviceId,
    required PlatformKeyReference currentEpoch,
    required String authenticationTicketId,
  });

  Future<void> authorizeNewData({
    required String deviceId,
    required PlatformKeyReference epochKey,
  });

  Future<void> destroyKey({
    required PlatformKeyReference key,
    required String authenticationTicketId,
  });
}

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, label, 'must not be blank');
  return value;
}
