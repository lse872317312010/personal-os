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

  test('failed unlock is redacted, closes, destroys key, and relocks', () async {
    final fixture = Fixture(schemaVersion: 0)..connection.tx.failMigration = true;

    await expectLater(
      fixture.driver.unlock(),
      throwsA(isA<VaultDriverFailure>().having(
        (error) => error.toString(),
        'redacted message',
        'VaultDriverFailure(vault_unlock_failed)',
      )),
    );
    expect(fixture.connection.closed, isTrue);
    expect(fixture.keys.leases.single.isDestroyed, isTrue);
    expect(fixture.driver.state, VaultLifecycleState.locked);
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
            .having((error) => error.code, 'code', 'vault_unlock_failed')
            .having(
              (error) => error.toString().contains('password'),
              'does not expose native error',
              isFalse,
            ),
      ),
    );
    expect(keys.leases.single.isDestroyed, isTrue);
  });

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
        'vault_rekey_failed',
      )),
    );
    expect(oldKey.isDestroyed, isFalse);
    expect(fixture.keys.leases.last.isDestroyed, isTrue);
  });

  test('lock tolerates close failure and destroys active lease', () async {
    final fixture = Fixture(schemaVersion: 2);
    await fixture.driver.unlock();
    fixture.connection.failClose = true;

    await fixture.driver.lock();

    expect(fixture.driver.state, VaultLifecycleState.locked);
    expect(fixture.keys.leases.single.isDestroyed, isTrue);
  });

  test('close is terminal and idempotent', () async {
    final fixture = Fixture(schemaVersion: 2);
    await fixture.driver.close();
    await fixture.driver.close();

    expect(fixture.driver.state, VaultLifecycleState.closed);
    await expectLater(fixture.driver.unlock(), throwsA(isA<VaultDriverFailure>()));
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

  @override
  Future<VaultKeyLease> acquire(VaultKeyPurpose purpose) async {
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
  Future<T> transaction<T>(Future<T> Function(VaultTransaction tx) action) async {
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
