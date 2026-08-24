import 'dart:async';

import 'package:personal_os_sqlite_vault_driver/sqlite_vault_driver.dart';
import 'package:test/test.dart';

void main() {
  test('unlock configures and migrates in one transaction', () async {
    final fixture = Fixture(schemaVersion: 0);
    await fixture.driver.unlock();

    expect(fixture.driver.state, VaultLifecycleState.unlocked);
    expect(fixture.connection.transactionCount, 1);
    expect(fixture.connection.tx.calls, <String>[
      'pragma:foreignKeysOn',
      'pragma:secureDeleteOn',
      'pragma:trustedSchemaOff',
      'schema',
      'migration:0-1',
      'migration:1-2',
    ]);
  });

  test('concurrent lifecycle calls are serialized through cleanup', () async {
    final fixture = Fixture(schemaVersion: 2);
    final acquireStarted = Completer<void>();
    final releaseAcquire = Completer<void>();
    fixture.keys.beforeAcquire = () async {
      acquireStarted.complete();
      await releaseAcquire.future;
    };

    final unlock = fixture.driver.unlock();
    await acquireStarted.future;
    final close = fixture.driver.close();

    expect(fixture.connection.transactionCount, 0);
    releaseAcquire.complete();
    await Future.wait<void>([unlock, close]);

    expect(fixture.driver.state, VaultLifecycleState.closed);
    expect(fixture.connection.closed, isTrue);
    expect(fixture.keys.leases.single.isDestroyed, isTrue);
  });

  test('a queued unlock cannot enter while the first unlock is opening',
      () async {
    final fixture = Fixture(schemaVersion: 2);
    final acquireStarted = Completer<void>();
    final releaseAcquire = Completer<void>();
    fixture.keys.beforeAcquire = () async {
      acquireStarted.complete();
      await releaseAcquire.future;
    };

    final first = fixture.driver.unlock();
    await acquireStarted.future;
    final second = fixture.driver.unlock();
    final secondFailure = expectLater(
      second,
      throwsA(isA<VaultDriverFailure>().having(
        (error) => error.code,
        'code',
        VaultDriverFailureCode.invalidLifecycleTransition,
      )),
    );

    expect(fixture.keys.leases, hasLength(0));
    releaseAcquire.complete();
    await first;
    await secondFailure;
    expect(fixture.keys.leases, hasLength(1));
  });

  test('failed unlock is redacted, closes, destroys key, and relocks',
      () async {
    final fixture = Fixture(schemaVersion: 0)
      ..connection.tx.failMigration = true;

    await expectLater(
      fixture.driver.unlock(),
      throwsA(isA<VaultDriverFailure>().having(
        (error) => error.toString(),
        'redacted message',
        'VaultDriverFailure(${VaultDriverFailureCode.vaultUnlockFailed})',
      )),
    );
    expect(fixture.connection.closed, isTrue);
    expect(fixture.keys.leases.single.isDestroyed, isTrue);
    expect(fixture.driver.state, VaultLifecycleState.locked);
  });

  test('failed lifecycle operation does not poison the serialized lane',
      () async {
    final fixture = Fixture(schemaVersion: 0)
      ..connection.tx.failMigration = true;

    await expectLater(
      fixture.driver.unlock(),
      throwsA(isA<VaultDriverFailure>()),
    );
    fixture.connection.tx.failMigration = false;

    await fixture.driver.unlock();
    expect(fixture.driver.state, VaultLifecycleState.unlocked);
    await fixture.driver.lock();
  });

  test('native open errors are replaced by a stable public code', () async {
    final keys = FakeKeys();
    final driver = VaultDriver(
      keyProvider: keys,
      opener: ThrowingOpener(),
      migrations: const <VaultMigration>[],
    );

    await expectLater(
      driver.unlock(),
      throwsA(
        isA<VaultDriverFailure>()
            .having(
              (error) => error.code,
              'code',
              VaultDriverFailureCode.vaultUnlockFailed,
            )
            .having(
              (error) => error.toString().contains('password'),
              'does not expose native error',
              isFalse,
            ),
      ),
    );
    expect(keys.leases.single.isDestroyed, isTrue);
    expect(driver.state, VaultLifecycleState.locked);
  });

  test(
    'failed open cleanup closes a returned connection and destroys the key',
    () async {
      final fixture = Fixture(schemaVersion: 0)
        ..connection.tx.failMigration = true
        ..connection.failClose = true;

      await expectLater(
        fixture.driver.unlock(),
        throwsA(isA<VaultDriverFailure>().having(
          (error) => error.code,
          'code',
          VaultDriverFailureCode.vaultUnlockFailed,
        )),
      );

      expect(fixture.connection.closed, isTrue);
      expect(fixture.keys.leases.single.isDestroyed, isTrue);
      expect(fixture.driver.state, VaultLifecycleState.locked);
    },
  );

  test('rekey commits before old key destruction', () async {
    final fixture = Fixture(schemaVersion: 2);
    await fixture.driver.unlock();
    final oldKey = fixture.keys.leases.single;

    await fixture.driver.rekey();

    expect(fixture.connection.tx.rekeyLease, same(fixture.keys.leases.last));
    expect(oldKey.isDestroyed, isTrue);
    expect(fixture.keys.leases.last.isDestroyed, isFalse);
  });

  test('failed rekey keeps old key live and destroys replacement', () async {
    final fixture = Fixture(schemaVersion: 2);
    await fixture.driver.unlock();
    final oldKey = fixture.keys.leases.single;
    fixture.connection.tx.failRekey = true;

    await expectLater(
      fixture.driver.rekey(),
      throwsA(isA<VaultDriverFailure>().having(
        (error) => error.code,
        'code',
        VaultDriverFailureCode.vaultRekeyFailed,
      )),
    );
    expect(oldKey.isDestroyed, isFalse);
    expect(fixture.keys.leases.last.isDestroyed, isTrue);
  });

  test(
    'rekey provider failure is redacted and leaves the active vault usable',
    () async {
      final fixture = Fixture(schemaVersion: 2);
      await fixture.driver.unlock();
      fixture.keys.failAcquire = true;

      await expectLater(
        fixture.driver.rekey(),
        throwsA(isA<VaultDriverFailure>().having(
          (error) => error.toString(),
          'redacted message',
          'VaultDriverFailure(${VaultDriverFailureCode.vaultRekeyFailed})',
        )),
      );
      expect(fixture.driver.state, VaultLifecycleState.unlocked);
      expect(fixture.keys.leases.single.isDestroyed, isFalse);
    },
  );

  test('lock tolerates close failure and destroys active lease', () async {
    final fixture = Fixture(schemaVersion: 2);
    await fixture.driver.unlock();
    fixture.connection.failClose = true;

    await fixture.driver.lock();

    expect(fixture.driver.state, VaultLifecycleState.locked);
    expect(fixture.keys.leases.single.isDestroyed, isTrue);
  });

  test('repeated lock is idempotent after cleanup', () async {
    final fixture = Fixture(schemaVersion: 2);
    await fixture.driver.unlock();

    await fixture.driver.lock();
    await fixture.driver.lock();

    expect(fixture.driver.state, VaultLifecycleState.locked);
    expect(fixture.connection.closed, isTrue);
    expect(fixture.keys.leases.single.isDestroyed, isTrue);
  });

  test('close is terminal and idempotent', () async {
    final fixture = Fixture(schemaVersion: 2);
    await fixture.driver.close();
    await fixture.driver.close();

    expect(fixture.driver.state, VaultLifecycleState.closed);
    await expectLater(
        fixture.driver.unlock(), throwsA(isA<VaultDriverFailure>()));
    await expectLater(
      fixture.driver.rekey(),
      throwsA(isA<VaultDriverFailure>().having(
        (error) => error.code,
        'code',
        VaultDriverFailureCode.vaultClosed,
      )),
    );
    await fixture.driver.lock();
    expect(fixture.driver.state, VaultLifecycleState.closed);
  });

  test('invalid migration chain is rejected before opening', () {
    expect(
      () => VaultDriver(
        keyProvider: FakeKeys(),
        opener: FakeOpener(FakeConnection(0)),
        migrations: const <VaultMigration>[
          VaultMigration(fromVersion: 0, toVersion: 1),
          VaultMigration(fromVersion: 2, toVersion: 3),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('migration cannot jump from a schema version before the chain',
      () async {
    final keys = FakeKeys();
    final connection = FakeConnection(0);
    final driver = VaultDriver(
      keyProvider: keys,
      opener: FakeOpener(connection),
      migrations: const <VaultMigration>[
        VaultMigration(fromVersion: 1, toVersion: 2),
      ],
    );

    await expectLater(
      driver.unlock(),
      throwsA(isA<VaultDriverFailure>().having(
        (error) => error.code,
        'code',
        VaultDriverFailureCode.vaultUnlockFailed,
      )),
    );
    expect(connection.tx.calls, <String>[
      'pragma:foreignKeysOn',
      'pragma:secureDeleteOn',
      'pragma:trustedSchemaOff',
      'schema',
    ]);
    expect(connection.closed, isTrue);
    expect(keys.leases.single.isDestroyed, isTrue);
    expect(driver.state, VaultLifecycleState.locked);
  });
}

final class Fixture {
  Fixture({required int schemaVersion})
      : keys = FakeKeys(),
        connection = FakeConnection(schemaVersion) {
    driver = VaultDriver(
      keyProvider: keys,
      opener: FakeOpener(connection),
      migrations: const <VaultMigration>[
        VaultMigration(fromVersion: 0, toVersion: 1),
        VaultMigration(fromVersion: 1, toVersion: 2),
      ],
    );
  }

  final FakeKeys keys;
  final FakeConnection connection;
  late final VaultDriver driver;
}

final class FakeLease implements VaultKeyLease {
  @override
  bool isDestroyed = false;

  @override
  Future<void> destroy() async => isDestroyed = true;
}

final class FakeKeys implements VaultKeyProvider {
  final leases = <FakeLease>[];
  bool failAcquire = false;
  Future<void> Function()? beforeAcquire;

  @override
  Future<VaultKeyLease> acquire(VaultKeyPurpose purpose) async {
    if (failAcquire)
      throw StateError('key alias and raw secret must not escape');
    await beforeAcquire?.call();
    final lease = FakeLease();
    leases.add(lease);
    return lease;
  }
}

final class FakeOpener implements VaultPlatformOpener {
  FakeOpener(this.connection);
  final FakeConnection connection;

  @override
  Future<VaultConnection> open(VaultKeyLease key) async => connection;
}

final class ThrowingOpener implements VaultPlatformOpener {
  @override
  Future<VaultConnection> open(VaultKeyLease key) async {
    throw StateError('password=should-never-escape');
  }
}

final class FakeConnection implements VaultConnection {
  FakeConnection(int schemaVersion) : tx = FakeTransaction(schemaVersion);
  final FakeTransaction tx;
  int transactionCount = 0;
  bool closed = false;
  bool failClose = false;

  @override
  Future<T> transaction<T>(
      Future<T> Function(VaultTransaction tx) action) async {
    transactionCount++;
    return action(tx);
  }

  @override
  Future<void> close() async {
    closed = true;
    if (failClose) throw StateError('native close included sensitive detail');
  }
}

final class FakeTransaction implements VaultTransaction {
  FakeTransaction(this.schemaVersion);
  int schemaVersion;
  final calls = <String>[];
  bool failMigration = false;
  bool failRekey = false;
  VaultKeyLease? rekeyLease;

  @override
  Future<void> applyPragma(VaultPragma pragma) async {
    calls.add('pragma:${pragma.name}');
  }

  @override
  Future<void> executeMigration(VaultMigration migration) async {
    calls.add('migration:${migration.fromVersion}-${migration.toVersion}');
    if (failMigration) throw StateError('native secret-bearing failure');
    schemaVersion = migration.toVersion;
  }

  @override
  Future<int> readSchemaVersion() async {
    calls.add('schema');
    return schemaVersion;
  }

  @override
  Future<void> rekey(VaultKeyLease newKey) async {
    rekeyLease = newKey;
    if (failRekey) throw StateError('raw platform error');
  }
}
