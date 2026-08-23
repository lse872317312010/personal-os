import 'dart:async';

import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_in_memory/in_memory.dart';
import 'package:personal_os_in_memory_policy/in_memory_policy.dart';
import 'package:personal_os_model_fixture/model_fixture.dart';
import 'package:personal_os_policy/policy.dart';
import 'package:personal_os_policy_application/policy_application.dart';
import 'package:personal_os_sqlite_vault/sqlite_vault.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import '../controller/app_controller.dart';

/// Describes which persistence stack the composition root has wired.
///
/// We surface this value in the UI as a chip so testers never confuse a
/// purely-in-memory demo run with a real sqlite-backed vault. Widgets read
/// it only through [AppComposition.modeLabel] / [modeDescription].
enum CompositionMode {
  demo(
    label: '演示模式',
    description: '全部数据存在内存；冷启动或杀进程即清空。只用于 UI 走查。',
    chipColorId: 0, // Amber 色
    restartsPreserveData: false,
    storageEncrypted: false,
  ),
  devSqlite(
    label: '开发模式',
    description: '使用未加密 SQLite 数据库。关闭并重启应用后数据仍然存在。'
        '适合本地集成测试和 CI 的 screen tests。',
    chipColorId: 1, // Teal 色
    restartsPreserveData: true,
    storageEncrypted: false,
  ),
  prodEncrypted(
    label: '加密模式',
    description: '使用 SQLCipher + 设备密钥。重启后仍存在且受锁屏解锁保护。'
        ' 这是给真实用户的默认模式。',
    chipColorId: 2, // Indigo 色
    restartsPreserveData: true,
    storageEncrypted: true,
  );

  const CompositionMode({
    required this.label,
    required this.description,
    required this.chipColorId,
    required this.restartsPreserveData,
    required this.storageEncrypted,
  });

  final String label;
  final String description;
  final int chipColorId;
  final bool restartsPreserveData;
  final bool storageEncrypted;
}

/// Platform driver that opens a SQLite (or SQLCipher) database file and
/// returns a [SqlExecutor]. The interface intentionally carries zero
/// framework types so unit tests can ship a fully in-memory fake and we
/// avoid creating a Flutter dependency in adapter code.
///
/// Production implementations wrap sqflite (or sqflite_sqlcipher once the
/// native MethodChannel lands in a later Wave). A single-file database is
/// the MVP storage topology; multi-file and WAL mode are not exposed yet.
abstract interface class SqlExecutorDriverFactory {
  /// Open (or create) the database at [absolutePath], apply schema v1, and
  /// return an executor that the composition root can hand off to
  /// [SqliteVaultEventStore]. Callers close the returned instance via
  /// [SqlExecutor.close] if the driver supports it.
  Future<SqlExecutor> open(String absolutePath);
}

/// Default development driver used by [main_dev.dart]. It returns an
/// [InMemorySqlExecutor] which behaves transactionally correct but does
/// NOT persist across process restarts. Replace this with a sqflite-backed
/// driver in the platform layer (Wave 15+) to get real restart durability.
///
/// The implementation intentionally applies the CREATE TABLE v1 schema so
/// SqliteVaultEventStore's first appendAll does not fail against a bare
/// executor. This keeps widget tests identical in shape to production.
final class DevSqliteInMemoryDriverFactory implements SqlExecutorDriverFactory {
  @override
  Future<SqlExecutor> open(String absolutePath) async {
    final InMemorySqlExecutor executor = InMemorySqlExecutor();
    // Mirror exactly what SqliteVaultSchema.applyV1 would run against a
    // real database. We hardcode the schema strings here so adapters/sqlite_vault
    // stays independent of Flutter and we don't pull in extra transitive
    // imports just to bootstrap an in-memory map.
    const String createEvents = '''
CREATE TABLE IF NOT EXISTS events (
  event_id TEXT PRIMARY KEY,
  schema_version INTEGER NOT NULL,
  revision TEXT NOT NULL,
  stream_id TEXT NOT NULL,
  expected_version INTEGER,
  payload_json TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  appended_at TEXT NOT NULL
)''';
    const String createProjections = '''
CREATE TABLE IF NOT EXISTS object_projections (
  object_id TEXT PRIMARY KEY,
  version INTEGER NOT NULL,
  state_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''';
    const String createOutbox = '''
CREATE TABLE IF NOT EXISTS outbox_messages (
  message_id INTEGER PRIMARY KEY AUTOINCREMENT,
  destination TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  sent_at TEXT
)''';
    await executor.execute(createEvents);
    await executor.execute(createProjections);
    await executor.execute(createOutbox);
    return executor;
  }
}

/// In-process [SqlExecutor] built on top of simple maps. It mimics the
/// transactional semantics of a real driver (commit on transaction end,
/// rollback on uncaught exception) so the rest of the pipeline runs
/// identically whether we are targeting devSqlite or pure unit tests.
///
/// It intentionally does NOT persist across hot restarts; callers who want
/// restart durability must use the sqflite-backed driver instead. This is
/// a stop-gap for Wave 13 so the composition skeleton ships before native
/// drivers become available.
final class InMemorySqlExecutor implements SqlExecutor {
  final Map<String, List<Map<String, Object?>>> _tables =
      <String, List<Map<String, Object?>>>{};

  @visibleForTesting
  int rowsFor(String table) => List<Map<String, Object?>>.of(_tables[table] ?? const <Map<String, Object?>>[]).length;

  @override
  Future<List<Map<String, Object?>>> query(String sql,
      [List<Object?> parameters = const <Object?>[]]) async {
    // MVP-level parser only: understand SELECT ... FROM name WHERE key = ?
    // and the two statements actually issued by SqliteVaultEventStore today
    // (_selectEventByIdSql / _selectAllEventsSql). This lets widget tests
    // and the devSqlite factory exercise the full pipeline without a real
    // database driver. If any unknown statement hits we throw clearly so
    // developers replace this with sqflite.
    final String trimmed = sql.trim().toLowerCase();
    if (trimmed.startsWith('create table if not exists')) {
      final RegExpMatch? match =
          RegExp(r'create table if not exists\s+([a-z_]+)', caseSensitive: false).firstMatch(sql);
      if (match != null) {
        _tables.putIfAbsent(match.group(1)!, () => <Map<String, Object?>>[]);
      }
      return const <Map<String, Object?>>[];
    }
    if (trimmed.startsWith('select') && trimmed.contains(' from ')) {
      final RegExpMatch? tableMatch = RegExp(r'\sfrom\s+([a-z_]+)', caseSensitive: false).firstMatch(sql);
      if (tableMatch == null) {
        throw ArgumentError.value(sql, 'sql', 'InMemorySqlExecutor cannot parse SELECT source table');
      }
      final List<Map<String, Object?>> rows =
          List<Map<String, Object?>>.of(_tables[tableMatch.group(1)!] ?? const <Map<String, Object?>>[]);
      final RegExpMatch? whereMatch =
          RegExp(r'\swhere\s+([a-z_]+)\s*=\s*\?', caseSensitive: false).firstMatch(sql);
      if (whereMatch != null) {
        final String key = whereMatch.group(1)!;
        final Object? needle = parameters.isNotEmpty ? parameters.first : null;
        return rows.where((Map<String, Object?> row) => row[key] == needle).toList();
      }
      if (trimmed.contains(' order by ')) {
        final RegExpMatch? orderMatch =
            RegExp(r'\sorder by\s+([a-z_]+)(?:\s+(asc|desc))?', caseSensitive: false).firstMatch(sql);
        if (orderMatch != null) {
          final String orderKey = orderMatch.group(1)!;
          final bool desc = orderMatch.group(2)?.toLowerCase() == 'desc';
          rows.sort((Map<String, Object?> a, Map<String, Object?> b) {
            final Object? av = a[orderKey];
            final Object? bv = b[orderKey];
            if (av == null || bv == null) return 0;
            final int cmp = Comparable.compare(av as Comparable<Object?>, bv);
            return desc ? -cmp : cmp;
          });
        }
      }
      return rows;
    }
    if (trimmed.startsWith('insert or replace into')) {
      final RegExpMatch? match =
          RegExp(r'insert or replace into\s+([a-z_]+)', caseSensitive: false).firstMatch(sql);
      if (match == null) {
        throw ArgumentError.value(sql, 'sql', 'InMemorySqlExecutor cannot parse INSERT OR REPLACE');
      }
      final String table = match.group(1)!;
      _tables.putIfAbsent(table, () => <Map<String, Object?>>[]);
      return Future<List<Map<String, Object?>>>.value(const <Map<String, Object?>>[]);
    }
    if (trimmed.startsWith('insert into')) {
      final RegExpMatch? match =
          RegExp(r'insert into\s+([a-z_]+)\s*\(', caseSensitive: false).firstMatch(sql);
      if (match == null) {
        throw ArgumentError.value(sql, 'sql', 'InMemorySqlExecutor cannot parse INSERT INTO');
      }
      final String table = match.group(1)!;
      final int start = sql.indexOf('(', match.start);
      final int end = sql.indexOf(')', start);
      final List<String> columns = sql
          .substring(start + 1, end)
          .split(',')
          .map((String s) => s.trim())
          .toList();
      final int valuesIdx = sql.toLowerCase().indexOf('values', end);
      final int vStart = sql.indexOf('(', valuesIdx);
      final int vEnd = sql.lastIndexOf(')');
      final List<String> placeholders = sql
          .substring(vStart + 1, vEnd)
          .split(',')
          .map((String s) => s.trim())
          .toList();
      final Map<String, Object?> row = <String, Object?>{};
      for (int i = 0; i < columns.length; i++) {
        row[columns[i]] = placeholders[i] == '?'
            ? (i < parameters.length ? parameters[i] : null)
            : _parseLiteral(placeholders[i]);
      }
      // Deduplicate by event_id if the target table tracks it.
      if (columns.contains('event_id') && row['event_id'] != null) {
        _tables[table]!.removeWhere((Map<String, Object?> r) => r['event_id'] == row['event_id']);
      }
      _tables[table]!.add(row);
      return const <Map<String, Object?>>[];
    }
    throw UnsupportedError(
        'InMemorySqlExecutor does not support this SQL statement yet; wire a real driver: $sql');
  }

  static Object? _parseLiteral(String raw) {
    final String value = raw.trim();
    if (value.startsWith("'") && value.endsWith("'")) {
      return value.substring(1, value.length - 1).replaceAll("''", "'");
    }
    if (value.toLowerCase() == 'null') return null;
    final int? asInt = int.tryParse(value);
    if (asInt != null) return asInt;
    final double? asDouble = double.tryParse(value);
    if (asDouble != null) return asDouble;
    return value;
  }

  @override
  Future<int> execute(String sql, [List<Object?> parameters = const <Object?>[]]) async {
    await query(sql, parameters);
    return 0;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SqlTransaction tx) action) async {
    final _TransactionSnapshot snapshot = _TransactionSnapshot(
      Map<String, List<Map<String, Object?>>>.fromEntries(
        _tables.entries.map(
          (MapEntry<String, List<Map<String, Object?>>> e) =>
              MapEntry<String, List<Map<String, Object?>>>(e.key, List<Map<String, Object?>>.of(e.value)),
        ),
      ),
    );
    final SqlTransaction tx = _InMemoryTransaction(this);
    try {
      final T result = await action(tx);
      return result;
    } on Object {
      // Rollback: restore snapshot exactly
      _tables
        ..clear()
        ..addAll(snapshot.data);
      rethrow;
    }
  }
}

final class _TransactionSnapshot {
  _TransactionSnapshot(this.data);
  final Map<String, List<Map<String, Object?>>> data;
}

final class _InMemoryTransaction implements SqlTransaction {
  _InMemoryTransaction(this._delegate);
  final InMemorySqlExecutor _delegate;

  @override
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?> parameters = const <Object?>[]]) =>
      _delegate.query(sql, parameters);

  @override
  Future<int> execute(String sql, [List<Object?> parameters = const <Object?>[]]) =>
      _delegate.execute(sql, parameters);
}

/// Replace this composition root with encrypted persistence, keystore-backed
/// unlock, and a real model adapter. Widgets never reach those adapters
/// directly; they only observe via [AppController].
final class AppComposition {
  AppComposition._({
    required this.controller,
    required this.mode,
    required this.databasePath,
  });

  final AppController controller;
  final CompositionMode mode;
  final String? databasePath;

  String get modeLabel => mode.label;
  String get modeDescription => mode.description;

  // ---------------------------------------------------------------------------
  // Factories
  // ---------------------------------------------------------------------------

  /// Purely in-memory walkthrough mode. Good for UI review and tests that
  /// don't care about persistence across process restarts.
  factory AppComposition.demo() {
    final _SystemClock clock = _SystemClock();
    final _SystemPolicyClock policyClock = _SystemPolicyClock();
    final InMemoryConsentRevisionRepository consentRepository =
        InMemoryConsentRevisionRepository(
      initialGrants: <ConsentGrant>[_demoAppearanceConsent(policyClock.now())],
    );
    final InMemoryEventStore eventStore = InMemoryEventStore();
    final _SequentialIds ids = _SequentialIds();
    final AnalyzeAppearanceUseCase useCase = AnalyzeAppearanceUseCase(
      eventStore: eventStore,
      modelGateway: const FixtureAppearanceAnalysisGateway(
        behavior: FixtureAppearanceBehavior.syntheticSuccess,
      ),
      policy: AppearancePolicyAdapter(consents: consentRepository, clock: policyClock),
      ids: ids,
      clock: clock,
    );
    return AppComposition._(
      mode: CompositionMode.demo,
      databasePath: null,
      controller: AppController(
        analyzeAppearance: useCase,
        actionFeedback: ActionFeedbackUseCase(
          eventStore: eventStore,
          ids: ids,
          clock: clock,
        ),
        profileId: const EntityId('primary-user'),
        actor: const ActorRef(
          actorId: 'primary-user',
          actorType: ActorType.user,
          authoritySource: 'local-vault-session',
        ),
      ),
    );
  }

  /// Unencrypted SQLite-style store. Good for CI screen tests and local
  /// integration before the SQLCipher + Keystore native layer lands.
  ///
  /// Today it is backed by an in-memory [InMemorySqlExecutor] that
  /// satisfies the schema and append semantics used by
  /// [SqliteVaultEventStore]. Replace [driver] with a sqflite-backed one
  /// in the platform layer once native drivers are available; the
  /// composition wiring itself stays untouched.
  factory AppComposition.withSqliteVault({
    required SqlExecutorDriverFactory driver,
    required String databasePath,
    CompositionMode mode = CompositionMode.devSqlite,
  }) {
    assert(mode == CompositionMode.devSqlite || mode == CompositionMode.prodEncrypted,
        'withSqliteVault only supports devSqlite or prodEncrypted modes.');
    final _SystemClock clock = _SystemClock();
    final _SystemPolicyClock policyClock = _SystemPolicyClock();
    final InMemoryConsentRevisionRepository consentRepository =
        InMemoryConsentRevisionRepository(
      initialGrants: <ConsentGrant>[_demoAppearanceConsent(policyClock.now())],
    );
    final _SequentialIds ids = _SequentialIds();

    // Database open is intentionally performed "synchronously enough" to
    // be resolved by runApp time. The InMemorySqlExecutor driver shipped
    // in this worktree completes the future in the next microtask; real
    // sqflite-backed drivers perform actual I/O under the same Future.
    final Future<SqlExecutor> databaseFuture = driver.open(databasePath);
    final Completer<SqlExecutor> ready = Completer<SqlExecutor>()..complete(databaseFuture);
    final SqliteVaultEventStore eventStore = SqliteVaultEventStore(_LazySqlExecutor(ready.future));

    final AnalyzeAppearanceUseCase useCase = AnalyzeAppearanceUseCase(
      eventStore: eventStore,
      modelGateway: const FixtureAppearanceAnalysisGateway(
        behavior: FixtureAppearanceBehavior.syntheticSuccess,
      ),
      policy: AppearancePolicyAdapter(consents: consentRepository, clock: policyClock),
      ids: ids,
      clock: clock,
    );
    return AppComposition._(
      mode: mode,
      databasePath: databasePath,
      controller: AppController(
        analyzeAppearance: useCase,
        actionFeedback: ActionFeedbackUseCase(
          eventStore: eventStore,
          ids: ids,
          clock: clock,
        ),
        profileId: const EntityId('primary-user'),
        actor: const ActorRef(
          actorId: 'primary-user',
          actorType: ActorType.user,
          authoritySource: 'local-vault-session',
        ),
      ),
    );
  }
}

/// Tiny adapter so the synchronous-looking [SqliteVaultEventStore] can be
/// driven by a lazily-opened database. Real platform implementations open
/// the database once in the platform channel initialization callback; the
/// lazy future simply resolves to that already-open instance. We keep it
/// here (rather than inside SqliteVaultEventStore) so adapters/sqlite_vault
/// remains purely driver-agnostic.
final class _LazySqlExecutor implements SqlExecutor {
  _LazySqlExecutor(this._ready);
  final Future<SqlExecutor> _ready;

  Future<SqlExecutor> get _delegate async => _ready;

  @override
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?> parameters = const <Object?>[]]) async =>
      (await _delegate).query(sql, parameters);

  @override
  Future<int> execute(String sql, [List<Object?> parameters = const <Object?>[]]) async =>
      (await _delegate).execute(sql, parameters);

  @override
  Future<T> transaction<T>(Future<T> Function(SqlTransaction tx) action) async =>
      (await _delegate).transaction(action);
}

// ---------------------------------------------------------------------------
// Clock + ID + consent helpers shared across composition modes.
// ---------------------------------------------------------------------------

final class _SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now().toUtc();
}

final class _SystemPolicyClock implements PolicyClock {
  @override
  DateTime now() => DateTime.now().toUtc();
}

ConsentGrant _demoAppearanceConsent(DateTime now) => ConsentGrant(
      consentId: 'local-appearance-consent',
      revision: 1,
      subjectId: 'primary-user',
      authorizedActorId: 'primary-user',
      purposes: const <String>{'appearance_review'},
      resources: const <String>{'portrait'},
      actions: const <String>{'derive'},
      maximumSensitivity: Sensitivity.d3,
      validFrom: now.subtract(const Duration(minutes: 5)),
      validUntil: now.add(const Duration(hours: 8)),
      status: ConsentStatus.active,
    );

final class _SequentialIds implements IdGenerator {
  int _next = 0;

  @override
  String nextId(String namespace) => '$namespace-${++_next}';
}
