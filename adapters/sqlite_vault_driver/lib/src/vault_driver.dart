/// Opaque reference to key material owned by a platform key provider.
///
/// There is intentionally no String or byte extraction API. A future native
/// driver receives the lease and must resolve it inside its trusted boundary.
abstract interface class VaultKeyLease {
  bool get isDestroyed;

  /// Releases and best-effort zeroizes any transient key material.
  Future<void> destroy();
}

abstract interface class VaultKeyProvider {
  Future<VaultKeyLease> acquire(VaultKeyPurpose purpose);
}

enum VaultKeyPurpose { unlock, rekey }

/// Opens a native database using an opaque key lease.
abstract interface class VaultPlatformOpener {
  Future<VaultConnection> open(VaultKeyLease key);
}

abstract interface class VaultConnection {
  Future<T> transaction<T>(Future<T> Function(VaultTransaction tx) action);
  Future<void> close();
}

abstract interface class VaultTransaction {
  /// Applies a fixed, implementation-owned safety setting.
  ///
  /// Callers cannot pass arbitrary PRAGMA text or key material.
  Future<void> applyPragma(VaultPragma pragma);

  Future<int> readSchemaVersion();
  Future<void> executeMigration(VaultMigration migration);

  /// Rekeys through the native boundary without a textual key representation.
  Future<void> rekey(VaultKeyLease newKey);
}

enum VaultPragma { foreignKeysOn, secureDeleteOn, trustedSchemaOff }

final class VaultMigration {
  const VaultMigration({required this.fromVersion, required this.toVersion});

  final int fromVersion;
  final int toVersion;
}

enum VaultLifecycleState { locked, opening, unlocked, closing, closed }

/// Wire-stable failure codes exposed by this driver boundary.
abstract final class VaultDriverFailureCode {
  static const invalidLifecycleTransition = 'invalid_lifecycle_transition';
  static const vaultClosed = 'vault_closed';
  static const vaultUnlockFailed = 'vault_unlock_failed';
  static const vaultRekeyFailed = 'vault_rekey_failed';
}

/// Stable, non-sensitive failure surfaced outside the adapter boundary.
final class VaultDriverFailure implements Exception {
  const VaultDriverFailure(this.code);

  final String code;

  @override
  String toString() => 'VaultDriverFailure($code)';
}

/// Coordinates open, safety PRAGMAs, migration, lock, and rekey ordering.
final class VaultDriver {
  VaultDriver({
    required VaultKeyProvider keyProvider,
    required VaultPlatformOpener opener,
    required List<VaultMigration> migrations,
  })  : _keyProvider = keyProvider,
        _opener = opener,
        _migrations = List<VaultMigration>.unmodifiable(migrations) {
    _validateMigrations(_migrations);
  }

  final VaultKeyProvider _keyProvider;
  final VaultPlatformOpener _opener;
  final List<VaultMigration> _migrations;
  VaultConnection? _connection;
  VaultKeyLease? _activeKey;
  VaultLifecycleState _state = VaultLifecycleState.locked;

  // Lifecycle calls may arrive concurrently from app and platform callbacks.
  // Keep the complete operation, including rollback and key disposal, in one
  // lane so no operation can observe a half-completed transition.
  Future<void> _operationTail = Future<void>.value();

  VaultLifecycleState get state => _state;

  Future<void> unlock() => _serialize(_unlock);

  Future<void> _unlock() async {
    _requireNotClosed();
    if (_state != VaultLifecycleState.locked) {
      throw const VaultDriverFailure(
        VaultDriverFailureCode.invalidLifecycleTransition,
      );
    }
    _state = VaultLifecycleState.opening;
    VaultKeyLease? lease;
    VaultConnection? connection;
    try {
      lease = await _keyProvider.acquire(VaultKeyPurpose.unlock);
      _requireLive(lease);
      connection = await _opener.open(lease);
      await connection.transaction((tx) async {
        await tx.applyPragma(VaultPragma.foreignKeysOn);
        await tx.applyPragma(VaultPragma.secureDeleteOn);
        await tx.applyPragma(VaultPragma.trustedSchemaOff);
        await _migrate(tx);
      });
      _activeKey = lease;
      _connection = connection;
      _state = VaultLifecycleState.unlocked;
    } catch (_) {
      await _bestEffortClose(connection);
      await _bestEffortDestroy(lease);
      _state = VaultLifecycleState.locked;
      throw const VaultDriverFailure(VaultDriverFailureCode.vaultUnlockFailed);
    }
  }

  Future<void> rekey() => _serialize(_rekey);

  Future<void> _rekey() async {
    _requireNotClosed();
    final connection = _connection;
    final prior = _activeKey;
    if (_state != VaultLifecycleState.unlocked ||
        connection == null ||
        prior == null) {
      throw const VaultDriverFailure(
        VaultDriverFailureCode.invalidLifecycleTransition,
      );
    }
    VaultKeyLease? replacement;
    try {
      replacement = await _keyProvider.acquire(VaultKeyPurpose.rekey);
      _requireLive(replacement);
      if (identical(replacement, prior)) throw StateError('same key lease');
      await connection.transaction((tx) => tx.rekey(replacement!));
    } catch (_) {
      if (!identical(replacement, prior)) {
        await _bestEffortDestroy(replacement);
      }
      throw const VaultDriverFailure(VaultDriverFailureCode.vaultRekeyFailed);
    }
    _activeKey = replacement;
    await _bestEffortDestroy(prior);
  }

  Future<void> lock() => _serialize(_lock);

  Future<void> _lock() async {
    // Lock is idempotent even after close. This is useful to fail closed from
    // teardown paths without introducing a second error surface.
    if (_state == VaultLifecycleState.locked ||
        _state == VaultLifecycleState.closed) {
      return;
    }
    if (_state != VaultLifecycleState.unlocked) {
      throw const VaultDriverFailure(
        VaultDriverFailureCode.invalidLifecycleTransition,
      );
    }
    _state = VaultLifecycleState.closing;
    final connection = _connection;
    final key = _activeKey;
    _connection = null;
    _activeKey = null;
    try {
      await connection?.close();
    } catch (_) {
      // Closing is best effort, but the reference is always discarded.
    } finally {
      await _bestEffortDestroy(key);
      _state = VaultLifecycleState.locked;
    }
  }

  Future<void> close() => _serialize(_close);

  Future<void> _close() async {
    if (_state == VaultLifecycleState.closed) return;
    if (_state == VaultLifecycleState.unlocked) await _lock();
    if (_state != VaultLifecycleState.locked) {
      throw const VaultDriverFailure(
        VaultDriverFailureCode.invalidLifecycleTransition,
      );
    }
    _state = VaultLifecycleState.closed;
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operationTail.then<T>((_) => operation());
    // Preserve the original stable failure for the caller, but keep the lane
    // usable for a later lock/close or recovery operation.
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  void _requireNotClosed() {
    if (_state == VaultLifecycleState.closed) {
      throw const VaultDriverFailure(VaultDriverFailureCode.vaultClosed);
    }
  }

  Future<void> _migrate(VaultTransaction tx) async {
    var version = await tx.readSchemaVersion();
    if (_migrations.isEmpty) return;

    final first = _migrations.first.fromVersion;
    final target = _migrations.last.toVersion;
    if (version < first || version > target) {
      throw StateError('unsupported schema version');
    }

    for (final migration in _migrations) {
      if (migration.fromVersion < version) continue;
      if (migration.fromVersion != version) {
        throw StateError('unsupported schema version');
      }
      await tx.executeMigration(migration);
      version = migration.toVersion;
      if (version == target) break;
    }
    if (version != target) throw StateError('unsupported schema version');
  }

  static void _validateMigrations(List<VaultMigration> migrations) {
    for (var index = 0; index < migrations.length; index++) {
      final item = migrations[index];
      if (item.fromVersion < 0 || item.toVersion != item.fromVersion + 1) {
        throw ArgumentError('migrations must advance exactly one version');
      }
      if (index > 0 && migrations[index - 1].toVersion != item.fromVersion) {
        throw ArgumentError('migrations must form one contiguous chain');
      }
    }
  }

  static void _requireLive(VaultKeyLease lease) {
    if (lease.isDestroyed) throw StateError('destroyed key lease');
  }
}

Future<void> _bestEffortClose(VaultConnection? connection) async {
  try {
    await connection?.close();
  } catch (_) {}
}

Future<void> _bestEffortDestroy(VaultKeyLease? lease) async {
  try {
    await lease?.destroy();
  } catch (_) {}
}
