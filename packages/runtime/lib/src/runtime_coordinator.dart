/// Platform-neutral ports used by the runtime composition root.
///
/// Concrete Flutter, database, sync, and model adapters belong outside this
/// package. Implementations must make stop/disable/lock operations idempotent.
abstract interface class RuntimeVault {
  Future<void> unlock();
  Future<void> lock();
  Future<void> close();
}

abstract interface class EventStoreAvailability {
  Future<void> makeAvailable();
  Future<void> makeUnavailable();
}

abstract interface class RuntimeSync {
  Future<void> start();
  Future<void> stop();
}

abstract interface class RuntimeModelAccess {
  Future<void> enable();
  Future<void> disable();
}

enum RuntimeState {
  locked,
  unlocking,
  foreground,
  background,
  locking,
  closed,
}

/// Stable error without nested platform messages or secret-bearing context.
final class RuntimeFailure implements Exception {
  const RuntimeFailure(this.code);

  final String code;

  @override
  String toString() => 'RuntimeFailure($code)';
}

/// Fail-closed coordinator for vault and dependent runtime services.
final class RuntimeCoordinator {
  RuntimeCoordinator({
    required RuntimeVault vault,
    required EventStoreAvailability eventStore,
    required RuntimeSync sync,
    required RuntimeModelAccess model,
  })  : _vault = vault,
        _eventStore = eventStore,
        _sync = sync,
        _model = model;

  final RuntimeVault _vault;
  final EventStoreAvailability _eventStore;
  final RuntimeSync _sync;
  final RuntimeModelAccess _model;

  RuntimeState _state = RuntimeState.locked;
  RuntimeState get state => _state;

  /// Unlocks the vault before exposing storage or starting dependent services.
  Future<void> unlock() async {
    if (_state == RuntimeState.foreground) return;
    _requireState(RuntimeState.locked);
    _state = RuntimeState.unlocking;
    try {
      await _vault.unlock();
      await _eventStore.makeAvailable();
      await _model.enable();
      await _sync.start();
      _state = RuntimeState.foreground;
    } catch (_) {
      await _bestEffortStopDependentsAndLock();
      _state = RuntimeState.locked;
      throw const RuntimeFailure('runtime_unlock_failed');
    }
  }

  /// Suspends network and model access while retaining the unlocked local vault.
  Future<void> enterBackground() async {
    if (_state == RuntimeState.background || _state == RuntimeState.locked) return;
    _requireState(RuntimeState.foreground);
    try {
      await _sync.stop();
      await _model.disable();
      _state = RuntimeState.background;
    } catch (_) {
      await _bestEffortStopDependentsAndLock();
      _state = RuntimeState.locked;
      throw const RuntimeFailure('runtime_background_failed');
    }
  }

  /// Restarts model and sync access only after a valid background transition.
  Future<void> enterForeground() async {
    if (_state == RuntimeState.foreground || _state == RuntimeState.locked) return;
    _requireState(RuntimeState.background);
    try {
      await _model.enable();
      await _sync.start();
      _state = RuntimeState.foreground;
    } catch (_) {
      await _bestEffortStopDependentsAndLock();
      _state = RuntimeState.locked;
      throw const RuntimeFailure('runtime_foreground_failed');
    }
  }

  /// Locks in dependency order: sync, model, event store, then vault.
  Future<void> lock() async {
    if (_state == RuntimeState.locked) return;
    if (_state == RuntimeState.closed) {
      throw const RuntimeFailure('invalid_runtime_transition');
    }
    if (_state != RuntimeState.foreground && _state != RuntimeState.background) {
      throw const RuntimeFailure('invalid_runtime_transition');
    }
    _state = RuntimeState.locking;
    var failed = false;
    failed = !await _attempt(_sync.stop) || failed;
    failed = !await _attempt(_model.disable) || failed;
    failed = !await _attempt(_eventStore.makeUnavailable) || failed;
    failed = !await _attempt(_vault.lock) || failed;
    _state = RuntimeState.locked;
    if (failed) throw const RuntimeFailure('runtime_lock_incomplete');
  }

  /// Permanently closes this coordinator after enforcing the lock boundary.
  Future<void> close() async {
    if (_state == RuntimeState.closed) return;
    if (_state == RuntimeState.foreground || _state == RuntimeState.background) {
      try {
        await lock();
      } on RuntimeFailure {
        // Continue to the terminal close boundary after best-effort lock.
      }
    }
    if (_state != RuntimeState.locked) {
      throw const RuntimeFailure('invalid_runtime_transition');
    }
    final succeeded = await _attempt(_vault.close);
    _state = RuntimeState.closed;
    if (!succeeded) throw const RuntimeFailure('runtime_close_incomplete');
  }

  void _requireState(RuntimeState expected) {
    if (_state != expected) {
      throw const RuntimeFailure('invalid_runtime_transition');
    }
  }

  Future<void> _bestEffortStopDependentsAndLock() async {
    await _attempt(_sync.stop);
    await _attempt(_model.disable);
    await _attempt(_eventStore.makeUnavailable);
    await _attempt(_vault.lock);
  }
}

Future<bool> _attempt(Future<void> Function() operation) async {
  try {
    await operation();
    return true;
  } catch (_) {
    return false;
  }
}
