import 'dart:typed_data';

import 'package:personal_os_security_api/security_api.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 20, 12);

  test('vault fails closed, unlocks with opaque grant, and locks again',
      () async {
    final session = DefaultVaultSession(
      _FakeUnlockPort(now.add(const Duration(minutes: 1))),
      clock: () => now,
    );

    expect(session.state, VaultSessionState.locked);
    expect(
      session.requireGrant,
      throwsA(_hasCode(SecurityErrorCode.vaultLocked)),
    );
    await session.unlock(reason: 'Open personal vault');
    expect(session.isUnlocked, isTrue);
    expect(session.requireGrant().id, 'grant-1');
    await session.lock();
    expect(session.isUnlocked, isFalse);
  });

  test('expired grants are rejected and cleared', () async {
    final session = DefaultVaultSession(
      _FakeUnlockPort(now.add(const Duration(seconds: 1))),
      clock: () => now,
    );
    await session.unlock(reason: 'Open personal vault');

    expect(
      () => session.requireGrant(at: now.add(const Duration(seconds: 1))),
      throwsA(_hasCode(SecurityErrorCode.unlockExpired)),
    );
    expect(session.state, VaultSessionState.locked);
  });

  test('fake provider wraps and unwraps without returning plaintext bytes',
      () async {
    final grant = UnlockGrant.opaque(
      id: 'grant-1',
      expiresAt: now.add(const Duration(minutes: 1)),
    );
    final provider = _FakeKeyProvider();
    final wrapping = await provider.createKey(
      purpose: KeyPurpose.deviceWrapping,
      grant: grant,
    );
    final blob =
        await provider.createKey(purpose: KeyPurpose.blob, grant: grant);
    final envelope = await provider.wrapKey(
      key: blob,
      wrappingKey: wrapping,
      grant: grant,
    );
    final restored = await provider.unwrapKey(
      wrappedKey: envelope,
      wrappingKey: wrapping,
      grant: grant,
    );

    expect(envelope.ciphertext, isNotEmpty);
    expect(restored.purpose, KeyPurpose.blob);
    expect(restored, isA<KeyHandle>());
  });

  test('revoked device cannot authorize future data on any epoch', () async {
    final grant = UnlockGrant.opaque(
      id: 'grant-1',
      expiresAt: now.add(const Duration(minutes: 1)),
    );
    final provider = _FakeKeyProvider();
    final epoch = await provider.createKey(
      purpose: KeyPurpose.accountEpoch,
      grant: grant,
    );
    final rotation = await provider.revokeDevice(
      deviceId: 'lost-phone',
      currentEpoch: epoch,
      grant: grant,
    );

    expect(rotation.current.version, epoch.version + 1);
    expect(
      provider.authorizeNewData(
        deviceId: 'lost-phone',
        epochKey: rotation.current,
      ),
      throwsA(_hasCode(SecurityErrorCode.deviceRevoked)),
    );
    await provider.authorizeNewData(
      deviceId: 'current-phone',
      epochKey: rotation.current,
    );
  });
}

Matcher _hasCode(SecurityErrorCode code) =>
    isA<SecurityException>().having((error) => error.code, 'code', code);

final class _FakeUnlockPort implements SecureUnlockPort {
  _FakeUnlockPort(this.expiresAt);

  final DateTime expiresAt;

  @override
  Future<UnlockGrant> requestUnlock(UnlockRequest request) async =>
      UnlockGrant.opaque(id: 'grant-1', expiresAt: expiresAt);
}

final class _FakeKeyProvider implements KeyProvider {
  final Map<String, KeyHandle> _keys = {};
  final Set<String> _revokedDevices = {};
  var _sequence = 0;

  @override
  Future<KeyHandle> createKey({
    required KeyPurpose purpose,
    required UnlockGrant grant,
  }) async {
    final handle = KeyHandle(
      id: 'key-${++_sequence}',
      purpose: purpose,
      version: 1,
    );
    _keys[handle.id] = handle;
    return handle;
  }

  @override
  Future<WrappedKey> wrapKey({
    required KeyHandle key,
    required KeyHandle wrappingKey,
    required UnlockGrant grant,
  }) async =>
      WrappedKey(
        keyId: key.id,
        keyPurpose: key.purpose,
        keyVersion: key.version,
        ciphertext: Uint8List.fromList([1, 2, 3]),
      );

  @override
  Future<KeyHandle> unwrapKey({
    required WrappedKey wrappedKey,
    required KeyHandle wrappingKey,
    required UnlockGrant grant,
  }) async =>
      KeyHandle(
        id: wrappedKey.keyId,
        purpose: wrappedKey.keyPurpose,
        version: wrappedKey.keyVersion,
      );

  @override
  Future<EpochRotation> rotateAccountEpoch({
    required KeyHandle currentEpoch,
    required UnlockGrant grant,
  }) async {
    final next = KeyHandle(
      id: 'key-${++_sequence}',
      purpose: KeyPurpose.accountEpoch,
      version: currentEpoch.version + 1,
    );
    _keys[next.id] = next;
    return EpochRotation(previous: currentEpoch, current: next);
  }

  @override
  Future<EpochRotation> revokeDevice({
    required String deviceId,
    required KeyHandle currentEpoch,
    required UnlockGrant grant,
  }) async {
    _revokedDevices.add(deviceId);
    return rotateAccountEpoch(currentEpoch: currentEpoch, grant: grant);
  }

  @override
  Future<void> authorizeNewData({
    required String deviceId,
    required KeyHandle epochKey,
  }) async {
    if (_revokedDevices.contains(deviceId)) {
      throw const SecurityException(SecurityErrorCode.deviceRevoked);
    }
  }

  @override
  Future<void> destroyKey({
    required KeyHandle key,
    required UnlockGrant grant,
  }) async {
    _keys.remove(key.id);
  }
}
