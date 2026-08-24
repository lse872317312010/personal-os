import 'dart:typed_data';

import 'package:personal_os_device_security/device_security.dart';
import 'package:personal_os_security_api/security_api.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 20, 12);
  late _FakeBridge bridge;
  late _RecordingLog log;
  late DeviceSecureUnlockAdapter unlock;
  late DeviceSecureVaultPort vault;
  late DeviceKeyProviderAdapter keys;
  late UnlockGrant grant;

  setUp(() {
    bridge = _FakeBridge(now: now);
    log = _RecordingLog();
    unlock = DeviceSecureUnlockAdapter(bridge, log: log);
    vault = DeviceSecureVaultPort(bridge, log: log, clock: () => now);
    keys = DeviceKeyProviderAdapter(bridge, log: log);
    grant = UnlockGrant.opaque(
      id: 'ticket-sensitive-value',
      expiresAt: now.add(const Duration(minutes: 1)),
    );
  });

  test('reports bridge capabilities without inventing hardware support',
      () async {
    bridge.capabilities = const DeviceSecurityCapabilities(
      protectionLevel: HardwareProtectionLevel.trustedEnvironment,
      userAuthenticationAvailable: true,
      deviceCredentialAvailable: true,
      nonExportableKeys: true,
      atomicDeviceRevocation: true,
    );

    final report = await unlock.inspectCapabilities();

    expect(report.protectionLevel, HardwareProtectionLevel.trustedEnvironment);
    expect(report.isHardwareBacked, isTrue);
    expect(report.protectionLevel, isNot(HardwareProtectionLevel.strongBox));
  });

  test('authentication request becomes an opaque short-lived grant', () async {
    final result = await unlock.requestUnlock(
      UnlockRequest(reason: 'Open private vault', allowDeviceCredential: false),
    );

    expect(result.id, 'native-ticket');
    expect(result.expiresAt, now.add(const Duration(seconds: 30)));
    expect(bridge.lastAuthentication!.reason, 'Open private vault');
    expect(bridge.lastAuthentication!.allowDeviceCredential, isFalse);
  });

  test('cancelled authentication maps to a stable domain error', () async {
    bridge.failure = const PlatformSecurityFailure(
      PlatformSecurityFailureCode.cancelled,
    );

    await expectLater(
      unlock.requestUnlock(UnlockRequest(reason: 'Open vault')),
      throwsA(_hasCode(SecurityErrorCode.unlockCancelled)),
    );
    expect(log.events.single.errorCode, 'security.unlock_cancelled');
  });

  test('key creation passes only purpose and opaque ticket ID', () async {
    final result =
        await keys.createKey(purpose: KeyPurpose.vaultMaster, grant: grant);

    expect(result.id, 'native-key-1');
    expect(result.purpose, KeyPurpose.vaultMaster);
    expect(bridge.lastTicketId, grant.id);
  });

  test('wrapped ciphertext is copied at both bridge boundaries', () async {
    final input = Uint8List.fromList([8, 9, 10]);
    bridge.wrappedCiphertext = input;
    final key = KeyHandle(id: 'data', purpose: KeyPurpose.blob, version: 1);
    final wrapping = KeyHandle(
      id: 'wrapping',
      purpose: KeyPurpose.deviceWrapping,
      version: 1,
    );

    final wrapped =
        await keys.wrapKey(key: key, wrappingKey: wrapping, grant: grant);
    input[0] = 0;
    final firstRead = wrapped.ciphertext;
    firstRead[1] = 0;

    expect(wrapped.ciphertext, [8, 9, 10]);

    await keys.unwrapKey(
        wrappedKey: wrapped, wrappingKey: wrapping, grant: grant);
    final captured = bridge.lastWrappedKey!.ciphertext;
    captured[2] = 0;
    expect(bridge.lastWrappedKey!.ciphertext, [8, 9, 10]);
  });

  test('revocation is one atomic bridge call and returns rotated epoch',
      () async {
    final current = KeyHandle(
      id: 'epoch-2',
      purpose: KeyPurpose.accountEpoch,
      version: 2,
    );

    final rotation = await keys.revokeDevice(
      deviceId: 'lost-device',
      currentEpoch: current,
      grant: grant,
    );

    expect(bridge.revokeCalls, 1);
    expect(bridge.rotateCalls, 0);
    expect(rotation.previous.version, 2);
    expect(rotation.current.version, 3);
  });

  test('revoked device failure maps and fails closed', () async {
    bridge.failure = const PlatformSecurityFailure(
      PlatformSecurityFailureCode.deviceRevoked,
    );

    expect(
      keys.authorizeNewData(
        deviceId: 'revoked-device',
        epochKey: KeyHandle(
          id: 'epoch',
          purpose: KeyPurpose.accountEpoch,
          version: 1,
        ),
      ),
      throwsA(_hasCode(SecurityErrorCode.deviceRevoked)),
    );
  });

  test('destroy delegates by opaque reference and authentication ticket',
      () async {
    final key =
        KeyHandle(id: 'delete-me', purpose: KeyPurpose.blob, version: 4);

    await keys.destroyKey(key: key, grant: grant);

    expect(bridge.destroyedKey!.id, 'delete-me');
    expect(bridge.lastTicketId, grant.id);
  });

  test('safe logs cannot contain reasons, IDs, ciphertext or native messages',
      () async {
    await unlock.requestUnlock(
      UnlockRequest(reason: 'SECRET reason with user details'),
    );
    await keys.createKey(purpose: KeyPurpose.recovery, grant: grant);
    bridge.failure = const PlatformSecurityFailure(
      PlatformSecurityFailureCode.unavailable,
    );
    await expectLater(
      keys.createKey(purpose: KeyPurpose.blob, grant: grant),
      throwsA(_hasCode(SecurityErrorCode.providerUnavailable)),
    );

    final rendered = log.events
        .map((event) => <String, Object?>{
              'operation': event.operation.name,
              'outcome': event.outcome.name,
              'errorCode': event.errorCode,
            })
        .toString();
    expect(rendered, isNot(contains('SECRET')));
    expect(rendered, isNot(contains('ticket-sensitive-value')));
    expect(rendered, isNot(contains('native-key-1')));
    expect(rendered, isNot(contains('[8, 9, 10]')));
  });

  test('all bridge failure codes map without exposing native exception text',
      () {
    const expected = <PlatformSecurityFailureCode, SecurityErrorCode>{
      PlatformSecurityFailureCode.cancelled: SecurityErrorCode.unlockCancelled,
      PlatformSecurityFailureCode.denied: SecurityErrorCode.unlockDenied,
      PlatformSecurityFailureCode.authenticationUnavailable:
          SecurityErrorCode.unlockUnavailable,
      PlatformSecurityFailureCode.authenticationExpired:
          SecurityErrorCode.unlockExpired,
      PlatformSecurityFailureCode.keyNotFound: SecurityErrorCode.keyNotFound,
      PlatformSecurityFailureCode.purposeMismatch:
          SecurityErrorCode.keyPurposeMismatch,
      PlatformSecurityFailureCode.keyDestroyed: SecurityErrorCode.keyDestroyed,
      PlatformSecurityFailureCode.invalidEnvelope:
          SecurityErrorCode.wrappedKeyInvalid,
      PlatformSecurityFailureCode.rotationConflict:
          SecurityErrorCode.rotationConflict,
      PlatformSecurityFailureCode.deviceRevoked:
          SecurityErrorCode.deviceRevoked,
      PlatformSecurityFailureCode.vaultLocked: SecurityErrorCode.vaultLocked,
      PlatformSecurityFailureCode.vaultSessionInvalid:
          SecurityErrorCode.vaultLocked,
      PlatformSecurityFailureCode.unavailable:
          SecurityErrorCode.providerUnavailable,
    };

    for (final entry in expected.entries) {
      final mapped =
          mapPlatformSecurityFailure(PlatformSecurityFailure(entry.key));
      expect(mapped.code, entry.value);
      expect(mapped.safeMessage, isNotEmpty);
      expect(mapped.toString(), isNot(contains('PlatformSecurityFailure')));
    }
  });

  test(
      'unexpected native authentication exception fails closed without text leakage',
      () async {
    bridge.unexpectedFailure = StateError(
      'SECRET native biometric diagnostics and account identity',
    );

    Object? caught;
    try {
      await unlock.requestUnlock(UnlockRequest(reason: 'Open vault'));
    } catch (error) {
      caught = error;
    }

    expect(caught, _hasCode(SecurityErrorCode.unlockUnavailable));
    expect(caught.toString(), isNot(contains('SECRET')));
    expect(log.events.single.errorCode, 'security.unlock_unavailable');
    expect(log.events.toString(), isNot(contains('biometric diagnostics')));
  });

  test('expired grant is rejected before opening the platform vault', () async {
    final expired = UnlockGrant.opaque(
      id: 'expired-ticket',
      expiresAt: now.subtract(const Duration(seconds: 1)),
    );

    await expectLater(
      vault.open(grant: expired),
      throwsA(_hasCode(SecurityErrorCode.unlockExpired)),
    );
    expect(bridge.openCalls, 0);
    expect(log.events.single.errorCode, 'security.unlock_expired');
  });

  test('platform open failure maps without leaking native text', () async {
    bridge.failure = const PlatformSecurityFailure(
      PlatformSecurityFailureCode.unavailable,
    );
    bridge.unexpectedFailure = StateError('SECRET database path and key alias');

    Object? caught;
    try {
      await vault.open(grant: grant);
    } catch (error) {
      caught = error;
    }

    expect(caught, _hasCode(SecurityErrorCode.providerUnavailable));
    expect(caught.toString(), isNot(contains('SECRET')));
    expect(log.events.single.errorCode, 'security.provider_unavailable');
  });

  test('opened session is opaque and close invalidates it', () async {
    final session = await vault.open(grant: grant);

    expect(session, isA<OpaqueVaultSession>());
    expect(session.isActive, isTrue);
    expect(session.toString(), isNot(contains('native-vault')));

    await vault.close(session);

    expect(session.isActive, isFalse);
    await expectLater(
      vault.close(session),
      throwsA(_hasCode(SecurityErrorCode.vaultLocked)),
    );
    expect(bridge.closeCalls, 1);
  });

  test('close failure still invalidates the opaque session and hides text',
      () async {
    final session = await vault.open(grant: grant);
    bridge.unexpectedFailure = StateError('SECRET native handle diagnostics');

    Object? caught;
    try {
      await vault.close(session);
    } catch (error) {
      caught = error;
    }

    expect(caught, _hasCode(SecurityErrorCode.providerUnavailable));
    expect(caught.toString(), isNot(contains('SECRET')));
    expect(session.isActive, isFalse);
    expect(log.events.last.errorCode, 'security.provider_unavailable');
  });

  test('unexpected native key exception fails closed without text leakage',
      () async {
    bridge.unexpectedFailure = StateError(
      'SECRET native keystore alias and device identity',
    );

    Object? caught;
    try {
      await keys.createKey(purpose: KeyPurpose.blob, grant: grant);
    } catch (error) {
      caught = error;
    }

    expect(caught, _hasCode(SecurityErrorCode.providerUnavailable));
    expect(caught.toString(), isNot(contains('SECRET')));
    expect(log.events.single.errorCode, 'security.provider_unavailable');
    expect(log.events.toString(), isNot(contains('keystore alias')));
  });
}

Matcher _hasCode(SecurityErrorCode code) =>
    isA<SecurityException>().having((error) => error.code, 'code', code);

final class _RecordingLog implements SafeSecurityLogSink {
  final List<SafeSecurityEvent> events = [];

  @override
  void record(SafeSecurityEvent event) => events.add(event);
}

final class _FakeBridge implements PlatformSecurityBridge {
  _FakeBridge({required this.now});

  final DateTime now;
  DeviceSecurityCapabilities capabilities = const DeviceSecurityCapabilities(
    protectionLevel: HardwareProtectionLevel.software,
    userAuthenticationAvailable: true,
    deviceCredentialAvailable: true,
    nonExportableKeys: false,
    atomicDeviceRevocation: true,
  );
  PlatformSecurityFailure? failure;
  Object? unexpectedFailure;
  PlatformAuthenticationRequest? lastAuthentication;
  String? lastTicketId;
  PlatformWrappedKey? lastWrappedKey;
  PlatformKeyReference? destroyedKey;
  Uint8List wrappedCiphertext = Uint8List.fromList([8, 9, 10]);
  int rotateCalls = 0;
  int revokeCalls = 0;
  int openCalls = 0;
  int closeCalls = 0;

  void _check() {
    final unexpected = unexpectedFailure;
    if (unexpected is Exception || unexpected is Error) throw unexpected;
    if (unexpected != null) throw StateError('unexpected native failure');
    final value = failure;
    if (value != null) throw value;
  }

  @override
  Future<DeviceSecurityCapabilities> inspectCapabilities() async {
    _check();
    return capabilities;
  }

  @override
  Future<PlatformAuthenticationTicket> authenticate(
    PlatformAuthenticationRequest request,
  ) async {
    _check();
    lastAuthentication = request;
    return PlatformAuthenticationTicket(
      id: 'native-ticket',
      expiresAt: now.add(const Duration(seconds: 30)),
    );
  }

  @override
  Future<PlatformVaultSession> openVault({
    required String authenticationTicketId,
    required DateTime ticketExpiresAt,
  }) async {
    _check();
    openCalls++;
    lastTicketId = authenticationTicketId;
    return PlatformVaultSession(id: 'native-vault');
  }

  @override
  Future<void> closeVault({required PlatformVaultSession session}) async {
    _check();
    closeCalls++;
  }

  @override
  Future<PlatformKeyReference> createKey({
    required KeyPurpose purpose,
    required String authenticationTicketId,
  }) async {
    _check();
    lastTicketId = authenticationTicketId;
    return PlatformKeyReference(
        id: 'native-key-1', purpose: purpose, version: 1);
  }

  @override
  Future<PlatformWrappedKey> wrapKey({
    required PlatformKeyReference key,
    required PlatformKeyReference wrappingKey,
    required String authenticationTicketId,
  }) async {
    _check();
    lastTicketId = authenticationTicketId;
    return PlatformWrappedKey(
      keyId: key.id,
      purpose: key.purpose,
      version: key.version,
      ciphertext: wrappedCiphertext,
    );
  }

  @override
  Future<PlatformKeyReference> unwrapKey({
    required PlatformWrappedKey wrappedKey,
    required PlatformKeyReference wrappingKey,
    required String authenticationTicketId,
  }) async {
    _check();
    lastWrappedKey = wrappedKey;
    lastTicketId = authenticationTicketId;
    return PlatformKeyReference(
      id: wrappedKey.keyId,
      purpose: wrappedKey.purpose,
      version: wrappedKey.version,
    );
  }

  @override
  Future<PlatformEpochRotation> rotateAccountEpoch({
    required PlatformKeyReference currentEpoch,
    required String authenticationTicketId,
  }) async {
    _check();
    rotateCalls++;
    return _rotation(currentEpoch);
  }

  @override
  Future<PlatformEpochRotation> revokeDeviceAndRotate({
    required String deviceId,
    required PlatformKeyReference currentEpoch,
    required String authenticationTicketId,
  }) async {
    _check();
    revokeCalls++;
    lastTicketId = authenticationTicketId;
    return _rotation(currentEpoch);
  }

  PlatformEpochRotation _rotation(PlatformKeyReference current) =>
      PlatformEpochRotation(
        previous: current,
        current: PlatformKeyReference(
          id: 'rotated-epoch',
          purpose: KeyPurpose.accountEpoch,
          version: current.version + 1,
        ),
      );

  @override
  Future<void> authorizeNewData({
    required String deviceId,
    required PlatformKeyReference epochKey,
  }) async =>
      _check();

  @override
  Future<void> destroyKey({
    required PlatformKeyReference key,
    required String authenticationTicketId,
  }) async {
    _check();
    destroyedKey = key;
    lastTicketId = authenticationTicketId;
  }
}
