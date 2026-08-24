import 'dart:typed_data';

import 'package:personal_os_recovery/recovery.dart';
import 'package:test/test.dart';

void main() {
  group('RecoverySession', () {
    test('applies security state before vault reads and unlocks once', () async {
      final fixture = Fixture();
      final secret = RecoverySecret([1, 2, 3]);

      final result = await fixture.session().restore(secret);

      expect(result.isSuccess, isTrue);
      expect(secret.isDestroyed, isTrue);
      expect(result.states, [
        RecoverySessionState.intake,
        RecoverySessionState.envelopeValidated,
        RecoverySessionState.packageAuthenticated,
        RecoverySessionState.accountVerified,
        RecoverySessionState.deviceBound,
        RecoverySessionState.securityStateSyncing,
        RecoverySessionState.deviceRevocationsApplied,
        RecoverySessionState.accountEpochApplied,
        RecoverySessionState.deletionTombstonesApplied,
        RecoverySessionState.securityStateApplied,
        RecoverySessionState.vaultDataSyncing,
        RecoverySessionState.consistencyVerified,
        RecoverySessionState.unlocked,
      ]);
      expect(result.states.map((state) => state.wireValue), [
        'intake',
        'envelope_validated',
        'package_authenticated',
        'account_verified',
        'device_bound',
        'security_state_syncing',
        'device_revocations_applied',
        'account_epoch_applied',
        'deletion_tombstones_applied',
        'security_state_applied',
        'vault_data_syncing',
        'consistency_verified',
        'unlocked',
      ]);
      expect(fixture.calls, [
        'authenticate',
        'account',
        'bind',
        'fetch-security',
        'revocations',
        'epoch',
        'tombstones',
        'commit-security',
        'sync-ciphertext',
        'consistency',
        'consume-and-rotate',
        'enable-reads',
      ]);
      expect(fixture.enableReadsCalled, isTrue);
      expect(fixture.audit.events.every((event) =>
          event.sessionId == 'session-opaque' &&
          event.packageId == 'package-opaque'), isTrue);
      expect(fixture.audit.events.first.generation, isNull);
      expect(fixture.audit.events[1].generation, isNull);
      expect(fixture.audit.events[2].generation, 7);
    });

    test('wrong code and corrupt ciphertext expose the same code', () async {
      for (final fault in [Fault.wrongCode, Fault.corruptCiphertext]) {
        final fixture = Fixture(fault: fault);
        final result = await fixture.session().restore(RecoverySecret([9]));
        expect(result.errorCode, RecoveryErrorCode.authFailed);
        expect(result.states, [
          RecoverySessionState.intake,
          RecoverySessionState.envelopeValidated,
          RecoverySessionState.failed,
        ]);
        expect(fixture.audit.events.every((event) => event.generation == null),
            isTrue);
        expect(fixture.enableReadsCalled, isFalse);
        expect(fixture.audit.events.last.errorCode,
            RecoveryErrorCode.authFailed);
      }
    });

    test('authentication receives a copy and the borrowed copy is wiped',
        () async {
      final fixture = Fixture();
      Uint8List? retained;
      fixture.authenticatorOverride = (envelope, secret) async {
        retained = secret;
        return AuthenticatedRecoveryPayload(
          accountBindingCommitment: 'opaque-commitment',
          generation: 7,
          securityStateAnchorRevision: 40,
          minimumAccountEpoch: 9,
        );
      };

      final original = RecoverySecret([4, 5, 6]);
      await fixture.session().restore(original);

      expect(original.isDestroyed, isTrue);
      expect(retained, orderedEquals([0, 0, 0]));
    });

    test('pre-auth rejection does not discard an unstarted staged state',
        () async {
      final fixture = Fixture(status: RecoveryPackageStatus.revoked);
      final result = await fixture.session().restore(RecoverySecret([1]));

      expect(result.errorCode, RecoveryErrorCode.packageRevoked);
      expect(fixture.calls, isEmpty);
    });

    test('post-commit failure never discards committed staged state', () async {
      final fixture = Fixture(fault: Fault.consistency);
      final result = await fixture.session().restore(RecoverySecret([1]));

      expect(result.errorCode, RecoveryErrorCode.consistencyFailed);
      expect(fixture.calls, contains('commit-security'));
      expect(fixture.calls, isNot(contains('discard-security')));
    });

    test('staged cleanup failure is reported without exposing adapter error',
        () async {
      final fixture = Fixture(
        fault: Fault.tombstones,
        discardFails: true,
      );
      final result = await fixture.session().restore(RecoverySecret([1]));

      expect(result.errorCode, RecoveryErrorCode.stagedStateCleanupFailed);
      expect(fixture.audit.events.last.errorCode,
          RecoveryErrorCode.stagedStateCleanupFailed);
    });

    test('security state rollback fails before any security application',
        () async {
      final fixture = Fixture(
        security: const SecurityStateSnapshot(
          revision: 42,
          accountEpoch: 9,
          signatureValid: true,
          accountBindingValid: true,
        ),
        anchorRevision: 43,
      );
      final result = await fixture.session().restore(RecoverySecret([1]));

      expect(result.errorCode, RecoveryErrorCode.securityStateRollback);
      expect(fixture.calls, contains('discard-security'));
      expect(fixture.calls, isNot(contains('revocations')));
      expect(fixture.enableReadsCalled, isFalse);
    });

    test('tombstone failure never commits security state or syncs vault',
        () async {
      final fixture = Fixture(fault: Fault.tombstones);
      final result = await fixture.session().restore(RecoverySecret([1]));

      expect(
        result.errorCode,
        RecoveryErrorCode.deletionTombstoneApplyFailed,
      );
      expect(fixture.calls, containsAllInOrder(['revocations', 'epoch', 'tombstones']));
      expect(fixture.calls, isNot(contains('commit-security')));
      expect(fixture.calls, isNot(contains('sync-ciphertext')));
      expect(fixture.enableReadsCalled, isFalse);
    });

    test('status gates reject duplicate superseded revoked and unverified',
        () async {
      final cases = {
        RecoveryPackageStatus.consumed: RecoveryErrorCode.alreadyConsumed,
        RecoveryPackageStatus.superseded: RecoveryErrorCode.packageSuperseded,
        RecoveryPackageStatus.revoked: RecoveryErrorCode.packageRevoked,
        RecoveryPackageStatus.generatedUnverified:
            RecoveryErrorCode.materialUnverified,
      };
      for (final entry in cases.entries) {
        final fixture = Fixture(status: entry.key);
        final secret = RecoverySecret([7]);
        final result = await fixture.session().restore(secret);
        expect(result.errorCode, entry.value);
        expect(fixture.calls, isEmpty);
        // Status is rejected before evaluation, but ownership was transferred
        // to restore and the bytes must still be cleared.
        expect(secret.isDestroyed, isTrue);
      }
    });

    test('lower ready generation is rejected only after authentication',
        () async {
      final fixture = Fixture(generation: 6, knownGeneration: 7);
      final result = await fixture.session().restore(RecoverySecret([1]));
      expect(result.errorCode, RecoveryErrorCode.packageSuperseded);
      expect(fixture.calls, ['authenticate']);
      expect(result.states, [
        RecoverySessionState.intake,
        RecoverySessionState.envelopeValidated,
        RecoverySessionState.packageAuthenticated,
        RecoverySessionState.failed,
      ]);
      expect(fixture.audit.events[1].generation, isNull);
      expect(fixture.audit.events[2].generation, 6);
    });

    test('a session is terminal and cannot be retried', () async {
      final fixture = Fixture(fault: Fault.wrongCode);
      final session = fixture.session();
      await session.restore(RecoverySecret([1]));
      final retrySecret = RecoverySecret([2]);
      await expectLater(
        session.restore(retrySecret),
        throwsA(isA<StateError>()),
      );
      expect(retrySecret.isDestroyed, isTrue);
    });

    test('audit structure has no field capable of carrying secret data', () {
      final event = RecoveryLogEvent(
        sessionId: 's',
        packageId: 'p',
        generation: 7,
        state: RecoverySessionState.failed,
        at: DateTime.utc(2026),
        errorCode: RecoveryErrorCode.authFailed,
      );
      expect(event.toString(), isNot(contains('recoveryCode')));
      expect(event.errorCode?.wireValue, 'RECOVERY_AUTH_FAILED');
    });
  });
}

enum Fault { none, wrongCode, corruptCiphertext, tombstones, consistency }

final class Fixture
    implements
        RecoveryEnvelopeAuthenticator,
        RecoveryAccountBindingPort,
        RecoveryDeviceBindingPort,
        RecoverySecurityStatePort,
        RecoveryVaultSyncPort,
        RecoveryConsumptionPort {
  Fixture({
    this.fault = Fault.none,
    this.status = RecoveryPackageStatus.recoveryReady,
    this.generation = 7,
    this.knownGeneration = 6,
    this.anchorRevision = 40,
    this.discardFails = false,
    this.security = const SecurityStateSnapshot(
      revision: 43,
      accountEpoch: 9,
      signatureValid: true,
      accountBindingValid: true,
    ),
  });

  final Fault fault;
  final RecoveryPackageStatus status;
  final int generation;
  final int knownGeneration;
  final int anchorRevision;
  final bool discardFails;
  final SecurityStateSnapshot security;
  final calls = <String>[];
  final audit = Audit();
  bool enableReadsCalled = false;
  Future<AuthenticatedRecoveryPayload> Function(
    RecoveryEnvelope,
    Uint8List,
  )? authenticatorOverride;

  RecoverySession session() => RecoverySession(
        sessionId: 'session-opaque',
        envelope: RecoveryEnvelope(
          packageId: 'package-opaque',
          formatVersion: 1,
          suiteId: 'TEST-ONLY-SYNTHETIC-v1',
        ),
        packageRecord: RecoveryPackageRecord(
          packageId: 'package-opaque',
          status: status,
        ),
        knownGeneration: knownGeneration,
        knownSecurityRevision: 40,
        supportedSuiteIds: const {'TEST-ONLY-SYNTHETIC-v1'},
        authenticator: this,
        accountBinding: this,
        deviceBinding: this,
        securityState: this,
        vaultSync: this,
        consumption: this,
        audit: audit,
        clock: () => DateTime.utc(2026),
      );

  @override
  Future<AuthenticatedRecoveryPayload> authenticate(
    RecoveryEnvelope envelope,
    Uint8List recoverySecret,
  ) async {
    calls.add('authenticate');
    final override = authenticatorOverride;
    if (override != null) return override(envelope, recoverySecret);
    if (fault == Fault.wrongCode || fault == Fault.corruptCiphertext) {
      throw const RecoveryFailure(RecoveryErrorCode.authFailed);
    }
    return AuthenticatedRecoveryPayload(
      accountBindingCommitment: 'opaque-commitment',
      generation: generation,
      securityStateAnchorRevision: anchorRevision,
      minimumAccountEpoch: 9,
    );
  }

  @override
  Future<bool> verify(String accountBindingCommitment) async {
    calls.add('account');
    return true;
  }

  @override
  Future<void> bindNewDevice() async => calls.add('bind');

  @override
  Future<SecurityStateSnapshot> fetchAndVerify() async {
    calls.add('fetch-security');
    return security;
  }

  @override
  Future<void> applyDeviceRevocations(SecurityStateSnapshot snapshot) async =>
      calls.add('revocations');

  @override
  Future<void> applyAccountEpoch(SecurityStateSnapshot snapshot) async =>
      calls.add('epoch');

  @override
  Future<void> applyDeletionTombstones(SecurityStateSnapshot snapshot) async {
    calls.add('tombstones');
    if (fault == Fault.tombstones) throw StateError('synthetic fault');
  }

  @override
  Future<void> commitStagedState(SecurityStateSnapshot snapshot) async =>
      calls.add('commit-security');

  @override
  Future<void> discardStagedState() async {
    calls.add('discard-security');
    if (discardFails) throw StateError('adapter path should not escape');
  }

  @override
  Future<void> syncCiphertextOnly() async => calls.add('sync-ciphertext');

  @override
  Future<bool> verifyConsistency() async {
    calls.add('consistency');
    if (fault == Fault.consistency) return false;
    return true;
  }

  @override
  Future<void> enableBusinessReads() async {
    calls.add('enable-reads');
    enableReadsCalled = true;
  }

  @override
  Future<void> consumeAndRequireRotation({
    required String packageId,
    required int generation,
  }) async => calls.add('consume-and-rotate');
}

final class Audit implements RecoveryAuditPort {
  final events = <RecoveryLogEvent>[];

  @override
  void record(RecoveryLogEvent event) => events.add(event);
}
