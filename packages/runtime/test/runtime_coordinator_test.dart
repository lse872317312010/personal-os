import 'dart:async';

import 'package:personal_os_runtime/runtime.dart';
import 'package:test/test.dart';

void main() {
  test('unlock starts services only after vault and store', () async {
    final fixture = Fixture();
    await fixture.runtime.unlock();

    expect(fixture.runtime.state, RuntimeState.foreground);
    expect(fixture.calls, <String>[
      'vault.unlock',
      'store.available',
      'model.enable',
      'sync.start',
    ]);
  });

  test('vault unlock failure never starts dependent services', () async {
    final fixture = Fixture()..vault.failUnlock = true;
    await expectLater(
      fixture.runtime.unlock(),
      throwsA(isA<RuntimeFailure>().having(
        (error) => error.code,
        'code',
        'runtime_unlock_failed',
      )),
    );

    expect(fixture.calls, <String>[
      'vault.unlock',
      'sync.stop',
      'model.disable',
      'store.unavailable',
      'vault.lock',
    ]);
    expect(fixture.runtime.state, RuntimeState.locked);
  });

  test('partial startup failure rolls back in dependency order', () async {
    final fixture = Fixture()..sync.failStart = true;
    await expectLater(fixture.runtime.unlock(), throwsA(isA<RuntimeFailure>()));

    expect(fixture.calls, <String>[
      'vault.unlock',
      'store.available',
      'model.enable',
      'sync.start',
      'sync.stop',
      'model.disable',
      'store.unavailable',
      'vault.lock',
    ]);
  });

  test('lock stops sync and model before store and vault', () async {
    final fixture = Fixture();
    await fixture.runtime.unlock();
    fixture.calls.clear();
    await fixture.runtime.lock();

    expect(fixture.calls, <String>[
      'sync.stop',
      'model.disable',
      'store.unavailable',
      'vault.lock',
    ]);
    expect(fixture.runtime.state, RuntimeState.locked);
  });

  test('background and foreground suspend and restore volatile services', () async {
    final fixture = Fixture();
    await fixture.runtime.unlock();
    fixture.calls.clear();

    await fixture.runtime.enterBackground();
    await fixture.runtime.enterBackground();
    await fixture.runtime.enterForeground();
    await fixture.runtime.enterForeground();

    expect(fixture.calls, <String>[
      'sync.stop',
      'model.disable',
      'model.enable',
      'sync.start',
    ]);
    expect(fixture.runtime.state, RuntimeState.foreground);
  });

  test('repeated unlock and lock are idempotent', () async {
    final fixture = Fixture();
    await fixture.runtime.unlock();
    await fixture.runtime.unlock();
    await fixture.runtime.lock();
    await fixture.runtime.lock();

    expect(fixture.calls.where((call) => call == 'vault.unlock'), hasLength(1));
    expect(fixture.calls.where((call) => call == 'vault.lock'), hasLength(1));
  });

  test('foreground failure locks all capabilities and redacts exception', () async {
    final fixture = Fixture();
    await fixture.runtime.unlock();
    await fixture.runtime.enterBackground();
    fixture.calls.clear();
    fixture.model.failEnable = true;

    await expectLater(
      fixture.runtime.enterForeground(),
      throwsA(
        isA<RuntimeFailure>()
            .having((error) => error.code, 'code', 'runtime_foreground_failed')
            .having(
              (error) => error.toString().contains('token'),
              'redacted',
              isFalse,
            ),
      ),
    );
    expect(fixture.runtime.state, RuntimeState.locked);
    expect(fixture.calls.last, 'vault.lock');
  });

  test('lock continues cleanup after failures and reports stable code', () async {
    final fixture = Fixture();
    await fixture.runtime.unlock();
    fixture.calls.clear();
    fixture.sync.failStop = true;

    await expectLater(
      fixture.runtime.lock(),
      throwsA(isA<RuntimeFailure>().having(
        (error) => error.code,
        'code',
        'runtime_lock_incomplete',
      )),
    );
    expect(fixture.calls, <String>[
      'sync.stop',
      'model.disable',
      'store.unavailable',
      'vault.lock',
    ]);
    expect(fixture.runtime.state, RuntimeState.locked);
  });

  test('close locks first and is terminal and idempotent', () async {
    final fixture = Fixture();
    await fixture.runtime.unlock();
    fixture.calls.clear();
    await fixture.runtime.close();
    await fixture.runtime.close();

    expect(fixture.calls, <String>[
      'sync.stop',
      'model.disable',
      'store.unavailable',
      'vault.lock',
      'vault.close',
    ]);
    expect(fixture.runtime.state, RuntimeState.closed);
  });

  test('concurrent lifecycle calls are serialized and remain idempotent', () async {
    final fixture = Fixture();
    final unlocks = await Future.wait([
      fixture.runtime.unlock(),
      fixture.runtime.unlock(),
    ]);

    expect(unlocks, hasLength(2));
    expect(fixture.runtime.state, RuntimeState.foreground);
    expect(fixture.calls.where((call) => call == 'vault.unlock'), hasLength(1));
  });

  test('close queued during startup cannot leave runtime foreground', () async {
    final fixture = Fixture();
    final unlockStarted = Completer<void>();
    final releaseUnlock = Completer<void>();
    fixture.vault.beforeUnlock = () async {
      unlockStarted.complete();
      await releaseUnlock.future;
    };

    final unlock = fixture.runtime.unlock();
    await unlockStarted.future;
    final close = fixture.runtime.close();
    releaseUnlock.complete();

    await Future.wait([unlock, close]);

    expect(fixture.runtime.state, RuntimeState.closed);
    expect(fixture.calls, <String>[
      'vault.unlock',
      'store.available',
      'model.enable',
      'sync.start',
      'sync.stop',
      'model.disable',
      'store.unavailable',
      'vault.lock',
      'vault.close',
    ]);
  });
}

final class Fixture {
  Fixture() {
    vault = FakeVault(calls);
    store = FakeStore(calls);
    sync = FakeSync(calls);
    model = FakeModel(calls);
    runtime = RuntimeCoordinator(
      vault: vault,
      eventStore: store,
      sync: sync,
      model: model,
    );
  }

  final calls = <String>[];
  late final FakeVault vault;
  late final FakeStore store;
  late final FakeSync sync;
  late final FakeModel model;
  late final RuntimeCoordinator runtime;
}

final class FakeVault implements RuntimeVault {
  FakeVault(this.calls);
  final List<String> calls;
  bool failUnlock = false;
  Future<void> Function()? beforeUnlock;

  @override
  Future<void> unlock() async {
    calls.add('vault.unlock');
    await beforeUnlock?.call();
    if (failUnlock) throw StateError('password=secret');
  }

  @override
  Future<void> lock() async {
    calls.add('vault.lock');
  }

  @override
  Future<void> close() async {
    calls.add('vault.close');
  }
}

final class FakeStore implements EventStoreAvailability {
  FakeStore(this.calls);
  final List<String> calls;

  @override
  Future<void> makeAvailable() async {
    calls.add('store.available');
  }

  @override
  Future<void> makeUnavailable() async {
    calls.add('store.unavailable');
  }
}

final class FakeSync implements RuntimeSync {
  FakeSync(this.calls);
  final List<String> calls;
  bool failStart = false;
  bool failStop = false;

  @override
  Future<void> start() async {
    calls.add('sync.start');
    if (failStart) throw StateError('token=secret');
  }

  @override
  Future<void> stop() async {
    calls.add('sync.stop');
    if (failStop) throw StateError('endpoint=secret');
  }
}

final class FakeModel implements RuntimeModelAccess {
  FakeModel(this.calls);
  final List<String> calls;
  bool failEnable = false;

  @override
  Future<void> enable() async {
    calls.add('model.enable');
    if (failEnable) throw StateError('token=secret');
  }

  @override
  Future<void> disable() async {
    calls.add('model.disable');
  }
}
