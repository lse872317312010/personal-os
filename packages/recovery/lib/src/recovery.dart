import 'dart:typed_data';

enum RecoverySessionState {
  intake,
  envelopeValidated,
  packageAuthenticated,
  accountVerified,
  deviceBound,
  securityStateSyncing,
  deviceRevocationsApplied,
  accountEpochApplied,
  deletionTombstonesApplied,
  securityStateApplied,
  vaultDataSyncing,
  consistencyVerified,
  unlocked,
  failed,
}

extension RecoverySessionStateWire on RecoverySessionState {
  String get wireValue => switch (this) {
        RecoverySessionState.intake => 'intake',
        RecoverySessionState.envelopeValidated => 'envelope_validated',
        RecoverySessionState.packageAuthenticated => 'package_authenticated',
        RecoverySessionState.accountVerified => 'account_verified',
        RecoverySessionState.deviceBound => 'device_bound',
        RecoverySessionState.securityStateSyncing => 'security_state_syncing',
        RecoverySessionState.deviceRevocationsApplied =>
          'device_revocations_applied',
        RecoverySessionState.accountEpochApplied => 'account_epoch_applied',
        RecoverySessionState.deletionTombstonesApplied =>
          'deletion_tombstones_applied',
        RecoverySessionState.securityStateApplied => 'security_state_applied',
        RecoverySessionState.vaultDataSyncing => 'vault_data_syncing',
        RecoverySessionState.consistencyVerified => 'consistency_verified',
        RecoverySessionState.unlocked => 'unlocked',
        RecoverySessionState.failed => 'failed',
      };
}

enum RecoveryPackageStatus {
  generatedUnverified,
  recoveryReady,
  superseded,
  revoked,
  consumed,
}

enum RecoveryErrorCode {
  packageMalformed('RECOVERY_PACKAGE_MALFORMED'),
  formatUnsupported('RECOVERY_FORMAT_UNSUPPORTED'),
  suiteUnsupported('RECOVERY_SUITE_UNSUPPORTED'),
  authFailed('RECOVERY_AUTH_FAILED'),
  accountMismatch('RECOVERY_ACCOUNT_MISMATCH'),
  packageRevoked('RECOVERY_PACKAGE_REVOKED'),
  packageSuperseded('RECOVERY_PACKAGE_SUPERSEDED'),
  alreadyConsumed('RECOVERY_ALREADY_CONSUMED'),
  materialUnverified('RECOVERY_MATERIAL_UNVERIFIED'),
  deviceBindingFailed('RECOVERY_DEVICE_BINDING_FAILED'),
  securityStateUnavailable('SECURITY_STATE_UNAVAILABLE'),
  securityStateSignatureInvalid('SECURITY_STATE_SIGNATURE_INVALID'),
  securityStateRollback('SECURITY_STATE_ROLLBACK'),
  deviceRevocationApplyFailed('DEVICE_REVOCATION_APPLY_FAILED'),
  deletionTombstoneApplyFailed('DELETION_TOMBSTONE_APPLY_FAILED'),
  consistencyFailed('RECOVERY_CONSISTENCY_FAILED');

  const RecoveryErrorCode(this.wireValue);
  final String wireValue;
}

final class RecoveryFailure implements Exception {
  const RecoveryFailure(this.code);
  final RecoveryErrorCode code;

  @override
  String toString() => 'RecoveryFailure(${code.wireValue})';
}

final class RecoveryEnvelope {
  const RecoveryEnvelope({
    required this.packageId,
    required this.formatVersion,
    required this.suiteId,
  });

  final String packageId;
  final int formatVersion;
  final String suiteId;
}

/// Trusted local package lifecycle metadata. This is never sourced from, or
/// serialized into, the Relay-visible recovery envelope.
final class RecoveryPackageRecord {
  const RecoveryPackageRecord({required this.status, this.packageId});

  final RecoveryPackageStatus status;
  final String? packageId;
}

/// Ephemeral caller-owned secret. The orchestrator never logs or retains it.
final class RecoverySecret {
  RecoverySecret(List<int> bytes) : _bytes = Uint8List.fromList(bytes);
  final Uint8List _bytes;
  bool _destroyed = false;

  Uint8List borrowForAuthentication() {
    if (_destroyed) throw StateError('Recovery secret already destroyed');
    return _bytes;
  }

  void destroy() {
    _bytes.fillRange(0, _bytes.length, 0);
    _destroyed = true;
  }

  bool get isDestroyed => _destroyed;
}

final class AuthenticatedRecoveryPayload {
  const AuthenticatedRecoveryPayload({
    required this.accountBindingCommitment,
    required this.generation,
    required this.securityStateAnchorRevision,
    required this.minimumAccountEpoch,
  });

  final String accountBindingCommitment;
  final int generation;
  final int securityStateAnchorRevision;
  final int minimumAccountEpoch;
}

final class SecurityStateSnapshot {
  const SecurityStateSnapshot({
    required this.revision,
    required this.accountEpoch,
    required this.signatureValid,
    required this.accountBindingValid,
  });

  final int revision;
  final int accountEpoch;
  final bool signatureValid;
  final bool accountBindingValid;
}

abstract interface class RecoveryEnvelopeAuthenticator {
  /// Production implementations MUST authenticate ciphertext and all security
  /// relevant associated data. Wrong code and corrupt ciphertext MUST both
  /// throw [RecoveryErrorCode.authFailed]. The borrowed secret MUST NOT be
  /// retained after this Future completes.
  Future<AuthenticatedRecoveryPayload> authenticate(
    RecoveryEnvelope envelope,
    Uint8List recoverySecret,
  );
}

abstract interface class RecoveryAccountBindingPort {
  Future<bool> verify(String accountBindingCommitment);
}

abstract interface class RecoveryDeviceBindingPort {
  Future<void> bindNewDevice();
}

abstract interface class RecoverySecurityStatePort {
  Future<SecurityStateSnapshot> fetchAndVerify();
  // These operations mutate an isolated staging store only. They become
  // visible atomically through commitStagedState.
  Future<void> applyDeviceRevocations(SecurityStateSnapshot snapshot);
  Future<void> applyAccountEpoch(SecurityStateSnapshot snapshot);
  Future<void> applyDeletionTombstones(SecurityStateSnapshot snapshot);
  Future<void> commitStagedState(SecurityStateSnapshot snapshot);
  Future<void> discardStagedState();
}

abstract interface class RecoveryVaultSyncPort {
  Future<void> syncCiphertextOnly();
  Future<bool> verifyConsistency();
  Future<void> enableBusinessReads();
}

abstract interface class RecoveryConsumptionPort {
  Future<void> consumeAndRequireRotation({
    required String packageId,
    required int generation,
  });
}

final class RecoveryLogEvent {
  const RecoveryLogEvent({
    required this.sessionId,
    required this.packageId,
    required this.generation,
    required this.state,
    required this.at,
    this.errorCode,
  });

  final String sessionId;
  final String packageId;
  /// Null until authenticated inner payload is available.
  final int? generation;
  final RecoverySessionState state;
  final DateTime at;
  final RecoveryErrorCode? errorCode;
}

abstract interface class RecoveryAuditPort {
  void record(RecoveryLogEvent event);
}

final class RecoveryResult {
  const RecoveryResult._(this.states, this.errorCode);
  final List<RecoverySessionState> states;
  final RecoveryErrorCode? errorCode;
  bool get isSuccess => errorCode == null;
}

final class RecoverySession {
  RecoverySession({
    required this.sessionId,
    required this.envelope,
    required this.packageRecord,
    required this.knownGeneration,
    required this.knownSecurityRevision,
    required this.supportedSuiteIds,
    required RecoveryEnvelopeAuthenticator authenticator,
    required RecoveryAccountBindingPort accountBinding,
    required RecoveryDeviceBindingPort deviceBinding,
    required RecoverySecurityStatePort securityState,
    required RecoveryVaultSyncPort vaultSync,
    required RecoveryConsumptionPort consumption,
    required RecoveryAuditPort audit,
    DateTime Function()? clock,
  })  : _authenticator = authenticator,
        _accountBinding = accountBinding,
        _deviceBinding = deviceBinding,
        _securityState = securityState,
        _vaultSync = vaultSync,
        _consumption = consumption,
        _audit = audit,
        _clock = clock ?? DateTime.now;

  final String sessionId;
  final RecoveryEnvelope envelope;
  final RecoveryPackageRecord packageRecord;
  final int knownGeneration;
  final int knownSecurityRevision;
  final Set<String> supportedSuiteIds;
  final RecoveryEnvelopeAuthenticator _authenticator;
  final RecoveryAccountBindingPort _accountBinding;
  final RecoveryDeviceBindingPort _deviceBinding;
  final RecoverySecurityStatePort _securityState;
  final RecoveryVaultSyncPort _vaultSync;
  final RecoveryConsumptionPort _consumption;
  final RecoveryAuditPort _audit;
  final DateTime Function() _clock;
  final List<RecoverySessionState> _states = [RecoverySessionState.intake];
  bool _started = false;
  int? _authenticatedGeneration;

  RecoverySessionState get state => _states.last;

  Future<RecoveryResult> restore(RecoverySecret secret) async {
    try {
      if (_started) throw StateError('Recovery session is single-use');
      _started = true;
      _log();
      try {
        _validateEnvelope();
        _advance(RecoverySessionState.envelopeValidated);
        _validateStatus();

        AuthenticatedRecoveryPayload payload;
        try {
          payload = await _authenticator.authenticate(
            envelope,
            secret.borrowForAuthentication(),
          );
        } on RecoveryFailure catch (error) {
          if (error.code == RecoveryErrorCode.authFailed) rethrow;
          throw const RecoveryFailure(RecoveryErrorCode.authFailed);
        } catch (_) {
          throw const RecoveryFailure(RecoveryErrorCode.authFailed);
        } finally {
          // Clear as soon as authentication finishes; the outer finally also
          // covers every path that rejects before authentication starts.
          secret.destroy();
        }
        _authenticatedGeneration = payload.generation;
        _advance(RecoverySessionState.packageAuthenticated);

        if (payload.generation < 1) {
          throw const RecoveryFailure(RecoveryErrorCode.packageMalformed);
        }
        if (payload.generation < knownGeneration) {
          throw const RecoveryFailure(RecoveryErrorCode.packageSuperseded);
        }
        if (!await _accountBinding.verify(payload.accountBindingCommitment)) {
          throw const RecoveryFailure(RecoveryErrorCode.accountMismatch);
        }
        _advance(RecoverySessionState.accountVerified);

        try {
          await _deviceBinding.bindNewDevice();
        } catch (_) {
          throw const RecoveryFailure(RecoveryErrorCode.deviceBindingFailed);
        }
        _advance(RecoverySessionState.deviceBound);
        _advance(RecoverySessionState.securityStateSyncing);

        final snapshot = await _fetchSecurityState();
        if (!snapshot.signatureValid || !snapshot.accountBindingValid) {
          throw const RecoveryFailure(
            RecoveryErrorCode.securityStateSignatureInvalid,
          );
        }
        if (snapshot.revision < knownSecurityRevision ||
            snapshot.revision < payload.securityStateAnchorRevision ||
            snapshot.accountEpoch < payload.minimumAccountEpoch) {
          throw const RecoveryFailure(RecoveryErrorCode.securityStateRollback);
        }

        try {
          await _securityState.applyDeviceRevocations(snapshot);
        } catch (_) {
          throw const RecoveryFailure(
            RecoveryErrorCode.deviceRevocationApplyFailed,
          );
        }
        _advance(RecoverySessionState.deviceRevocationsApplied);
        try {
          await _securityState.applyAccountEpoch(snapshot);
        } catch (_) {
          throw const RecoveryFailure(RecoveryErrorCode.securityStateRollback);
        }
        _advance(RecoverySessionState.accountEpochApplied);
        try {
          await _securityState.applyDeletionTombstones(snapshot);
        } catch (_) {
          throw const RecoveryFailure(
            RecoveryErrorCode.deletionTombstoneApplyFailed,
          );
        }
        _advance(RecoverySessionState.deletionTombstonesApplied);
        await _securityState.commitStagedState(snapshot);
        _advance(RecoverySessionState.securityStateApplied);

        await _vaultSync.syncCiphertextOnly();
        _advance(RecoverySessionState.vaultDataSyncing);
        if (!await _vaultSync.verifyConsistency()) {
          throw const RecoveryFailure(RecoveryErrorCode.consistencyFailed);
        }
        _advance(RecoverySessionState.consistencyVerified);

        // Consumption and rotation requirement are durable before reads unlock.
        await _consumption.consumeAndRequireRotation(
          packageId: envelope.packageId,
          generation: payload.generation,
        );
        await _vaultSync.enableBusinessReads();
        _advance(RecoverySessionState.unlocked);
        return RecoveryResult._(List.unmodifiable(_states), null);
      } on RecoveryFailure catch (error) {
        await _discardBestEffort();
        _fail(error.code);
        return RecoveryResult._(List.unmodifiable(_states), error.code);
      } catch (_) {
        await _discardBestEffort();
        _fail(RecoveryErrorCode.consistencyFailed);
        return RecoveryResult._(
          List.unmodifiable(_states),
          RecoveryErrorCode.consistencyFailed,
        );
      }
    } finally {
      // Calling restore transfers lifecycle responsibility for the secret,
      // including malformed/status-gated and already-terminal session paths.
      secret.destroy();
    }
  }

  void _validateEnvelope() {
    if (envelope.packageId.isEmpty) {
      throw const RecoveryFailure(RecoveryErrorCode.packageMalformed);
    }
    if (envelope.formatVersion != 1) {
      throw const RecoveryFailure(RecoveryErrorCode.formatUnsupported);
    }
    if (envelope.suiteId.isEmpty ||
        !supportedSuiteIds.contains(envelope.suiteId)) {
      throw const RecoveryFailure(RecoveryErrorCode.suiteUnsupported);
    }
  }

  void _validateStatus() {
    final boundPackageId = packageRecord.packageId;
    if (boundPackageId != null && boundPackageId != envelope.packageId) {
      throw const RecoveryFailure(RecoveryErrorCode.packageMalformed);
    }
    switch (packageRecord.status) {
      case RecoveryPackageStatus.generatedUnverified:
        throw const RecoveryFailure(RecoveryErrorCode.materialUnverified);
      case RecoveryPackageStatus.superseded:
        throw const RecoveryFailure(RecoveryErrorCode.packageSuperseded);
      case RecoveryPackageStatus.revoked:
        throw const RecoveryFailure(RecoveryErrorCode.packageRevoked);
      case RecoveryPackageStatus.consumed:
        throw const RecoveryFailure(RecoveryErrorCode.alreadyConsumed);
      case RecoveryPackageStatus.recoveryReady:
        return;
    }
  }

  Future<SecurityStateSnapshot> _fetchSecurityState() async {
    try {
      return await _securityState.fetchAndVerify();
    } on RecoveryFailure {
      rethrow;
    } catch (_) {
      throw const RecoveryFailure(RecoveryErrorCode.securityStateUnavailable);
    }
  }

  Future<void> _discardBestEffort() async {
    // Only discard staged security state if we have reached the security
    // sync phase. Earlier failures (status gates, auth, generation, account
    // or device binding) never fetched or staged security state, so calling
    // discard would be an unnecessary observable side effect.
    if (state.index < RecoverySessionState.securityStateSyncing.index) {
      return;
    }
    try {
      await _securityState.discardStagedState();
    } catch (_) {}
  }

  void _advance(RecoverySessionState next) {
    if (state == RecoverySessionState.failed ||
        state == RecoverySessionState.unlocked ||
        next.index <= state.index) {
      throw StateError('Recovery state cannot move backward or leave terminal');
    }
    _states.add(next);
    _log();
  }

  void _fail(RecoveryErrorCode code) {
    if (state == RecoverySessionState.failed ||
        state == RecoverySessionState.unlocked) {
      throw StateError('Recovery session already terminal');
    }
    _states.add(RecoverySessionState.failed);
    _log(errorCode: code);
  }

  void _log({RecoveryErrorCode? errorCode}) => _audit.record(
        RecoveryLogEvent(
          sessionId: sessionId,
          packageId: envelope.packageId,
          generation: _authenticatedGeneration,
          state: state,
          at: _clock(),
          errorCode: errorCode,
        ),
      );
}
