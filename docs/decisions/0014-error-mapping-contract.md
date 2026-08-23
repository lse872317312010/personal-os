# 0014 — 持久化层错误映射契约（Error Mapping Contract）

日期：2026-08-23  
状态：proposed

## 背景

ADR-0013 已经把持久化层接口（`EventStore` / `BlobStore` / `KeyProvider` / `SecureUnlockPort` / `VaultSession` / `VaultDriver`）和适配器选择规则冻结成契约，但留下一个明确的未解决问题：

> 适配器内部仍可能在不同平台暴露不同错误码（`VaultDriverFailure` vs `SecurityException`）；本契约只约束接口，不约束错误转换，后续需要一份 error mapping 表。

实际代码里已经出现至少四类异常并存：

1. `EventAppendConflict`（`packages/storage_api/lib/src/event_store.dart`）— `EventStore.appendAll` 的 revision 冲突或 event_id 碰撞；
2. `VaultSchemaViolation`（`adapters/sqlite_vault/lib/sqlite_vault_schema.dart`）— `SqliteVaultEventStore._validate` 对 D4 / forbidden secret field / missing subject 的拒绝；
3. `BlobAccessDenied`（`packages/storage_api/lib/src/blob_store.dart`）— `BlobStore.put` 对 D4 的拒绝，已含稳定 `code`；
4. `SecurityException` + `SecurityErrorCode`（`packages/security_api/lib/src/security_error.dart`）— `VaultSession.requireGrant` 与 `KeyProvider` 的稳定错误码；
5. `VaultDriverFailure`（`adapters/sqlite_vault_driver/lib/src/vault_driver.dart`）— Vault 生命周期 / rekey / 迁移失败，仅含稳定 `code`；
6. 裸 `StateError` — `InMemoryEventStore.appendAll` 在非 revision 冲突时抛出，**没有稳定 reason code**，是当前最大的不一致点。

如果不在 ADR-0013 落地前补一份错误映射契约，会出现：

- 调用方（`runtime_coordinator`、`recovery`、`sync_worker`、UI controller）不得不 `try { ... } on VaultSchemaViolation { ... } on EventAppendConflict { ... } on StateError { ... }` 把内部异常类型漏到上层；
- 同一语义（“D4 被拒绝”）在 `BlobStore.put` 是 `BlobAccessDenied`，在 `EventStore.appendAll` 的 `InMemoryEventStore` 走 `StateError('event_append_rejected:d4_persistence_forbidden')`、`SqliteVaultEventStore` 走 `VaultSchemaViolation('D4 cannot enter persistent storage')`，调用方难以写跨适配器一致的兜底；
- 日志和安全事件无法稳定聚合：`SecurityException` 已有 `wireValue`，但 `EventAppendConflict` / `VaultSchemaViolation` / `VaultDriverFailure` 都是字符串字段，没有枚举值，容易在文案改写时破坏机器解析；
- 跨平台（Windows DPAPI、iOS Keychain）落地时再补一份映射会重复返工。

## 决定

### 1. 引入 `PersistenceError` 共载类型

在 `packages/storage_api` 新增一个共载异常类型，作为持久化层对外的稳定失败信号；适配器内部异常仍然存在，但**对外公开的失败路径**必须能被映射到 `PersistenceError`：

```dart
/// Stable, machine-readable failures crossing the persistence layer.
///
/// Internal adapter exceptions (VaultSchemaViolation, EventAppendConflict,
/// VaultDriverFailure, SecurityException, ArgumentError) may be thrown
/// directly today, but callers are encouraged to catch PersistenceError
/// for cross-adapter parity. ADR-0014 governs the wire value space.
final class PersistenceError implements Exception {
  const PersistenceError(this.code, {this.cause, this.safeMessage});

  final PersistenceErrorCode code;
  final Object? cause;
  final String? safeMessage;

  /// Stable wire value (`persistence.*`) safe for logs and evidence ledger.
  String get wireValue => code.wireValue;

  @override
  String toString() => 'PersistenceError(${code.wireValue})';
}
```

### 2. `PersistenceErrorCode` 稳定码表

新增 `PersistenceErrorCode` 枚举，覆盖 ADR-0013 列出的所有失败语义。`wireValue` 以 `persistence.` 为前缀，避免与 `security.*`（`SecurityErrorCode`）混淆：

| code | wireValue | 触发场景 | 原内部异常 |
| --- | --- | --- | --- |
| `vaultLocked` | `persistence.vault_locked` | 写入时 `VaultSession` 未解锁或 grant 已过期 | `SecurityException(vaultLocked)` / `SecurityException(unlockExpired)` |
| `vaultUnlockFailed` | `persistence.vault_unlock_failed` | `VaultDriver.unlock` 失败 | `VaultDriverFailure('vault_unlock_failed')` |
| `vaultRekeyFailed` | `persistence.vault_rekey_failed` | `VaultDriver.rekey` 失败 | `VaultDriverFailure('vault_rekey_failed')` |
| `vaultLifecycleInvalid` | `persistence.vault_lifecycle_invalid` | Vault 状态机非法转移 | `VaultDriverFailure('invalid_lifecycle_transition')` |
| `eventAppendConflict` | `persistence.event_append_conflict` | revision 冲突或 event_id 碰撞 | `EventAppendConflict` |
| `eventAppendRejected` | `persistence.event_append_rejected` | reducer 拒绝非冲突事件（含 missing_subject 等） | `StateError('event_append_rejected:...')` / `VaultSchemaViolation('... missing_subject')` |
| `d4PersistenceForbidden` | `persistence.d4_persistence_forbidden` | D4 数据尝试持久化 | `BlobAccessDenied.d4PersistenceForbidden` / `VaultSchemaViolation('D4 cannot enter persistent storage')` / `AppendResult.rejected(reasonCode: 'd4_persistence_forbidden')` |
| `sensitivityForbidden` | `persistence.sensitivity_forbidden` | 非 D4 但仍不在 `persistedSensitivities` 集合 | `VaultSchemaViolation('Sensitivity X cannot be persisted')` |
| `forbiddenSecretField` | `persistence.forbidden_secret_field` | payload 包含命名疑似敏感字段 | `VaultSchemaViolation('Forbidden secret field at ...')` |
| `keyNotFound` | `persistence.key_not_found` | `KeyProvider` 找不到 key handle | `SecurityException(keyNotFound)` |
| `keyPurposeMismatch` | `persistence.key_purpose_mismatch` | key purpose 与请求不符 | `SecurityException(keyPurposeMismatch)` |
| `keyDestroyed` | `persistence.key_destroyed` | 操作已销毁的 key lease | `SecurityException(keyDestroyed)` |
| `keyRotationConflict` | `persistence.key_rotation_conflict` | epoch 轮换冲突 | `SecurityException(rotationConflict)` |
| `deviceRevoked` | `persistence.device_revoked` | 设备已撤销仍尝试新数据加密 | `SecurityException(deviceRevoked)` |
| `providerUnavailable` | `persistence.provider_unavailable` | Keystore / 平台安全模块不可用 | `SecurityException(providerUnavailable)` / `VaultDriverFailure` |
| `invalidArgument` | `persistence.invalid_argument` | 入参校验失败（如 `limit < 0`、空 token） | `ArgumentError.value(...)` |
| `internalAdapterFailure` | `persistence.internal_adapter_failure` | 未分类的适配器内部失败 | 任何 `Object` 兜底 |

未在表中的失败一律归入 `internalAdapterFailure`，**不得**抛裸 `StateError` 或 `Exception('...')` 到调用方。

### 3. 适配器义务

每个持久化层适配器（`InMemoryEventStore`、`SqliteVaultEventStore`、未来的 SQLCipher BlobStore、`VaultDriver` 各平台实现、`KeyProvider` 实现）必须满足：

1. **保留内部异常类型以方便单元测试**：现有 `EventAppendConflict` / `VaultSchemaViolation` / `BlobAccessDenied` 不被立刻替换，避免破坏已有测试。
2. **在跨边界出口映射为 `PersistenceError`**：通过 `try { ... } on InternalException catch (e) { throw PersistenceError(code, cause: e, safeMessage: ...); }` 或一个集中的 `PersistenceErrorMapper`（见下节）转换。M2 阶段先在 `runtime_coordinator` 与 `recovery` 出口做映射；适配器内部直接抛原异常。
3. **`safeMessage` 不得包含密钥、路径、设备指纹**：与 `SecurityException.safeMessage` 同语义；可记录人类可读的失败原因，但禁止泄露 `BlobRef._token`、`VaultKeyLease` 任何字段、SQL 片段、文件路径。
4. **`cause` 用于调试，不进 evidence**：`cause` 字段可以携带原内部异常以便日志排查，但 evidence ledger（ADR-0010）只记录 `wireValue` 与 `safeMessage`，不记录 `cause.toString()`。
5. **稳定码不得随文案改动**：`wireValue` 由 ADR 控制；任何新增 / 重命名 / 删除必须出新 ADR 并标注 `supersedes`，与 `SecurityErrorCode` 同样严格。

### 4. `PersistenceErrorMapper` 集中映射器

在 `packages/storage_api` 新增 `PersistenceErrorMapper`，集中处理内部异常到 `PersistenceError` 的映射，避免调用方各自实现：

```dart
/// Central mapper from internal adapter exceptions to PersistenceError.
///
/// Callers at the boundary (runtime_coordinator, recovery, sync_worker,
/// UI controller) MUST route persistence-layer failures through this
/// mapper rather than catching internal types directly.
final class PersistenceErrorMapper {
  const PersistenceErrorMapper._();

  static PersistenceError map(Object error, {StackTrace? stackTrace}) {
    if (error is PersistenceError) return error;
    if (error is SecurityException) {
      return PersistenceError(_mapSecurity(error.code),
          cause: error, safeMessage: error.safeMessage);
    }
    if (error is BlobAccessDenied) {
      return switch (error.code) {
        'D4_PERSISTENCE_FORBIDDEN' => PersistenceError(
            PersistenceErrorCode.d4PersistenceForbidden,
            cause: error, safeMessage: error.reason),
        _ => PersistenceError(PersistenceErrorCode.internalAdapterFailure,
            cause: error, safeMessage: error.code),
      };
    }
    if (error is EventAppendConflict) {
      return PersistenceError(PersistenceErrorCode.eventAppendConflict,
          cause: error, safeMessage: error.message);
    }
    if (error is VaultSchemaViolation) {
      final code = _mapSchema(error.message);
      return PersistenceError(code, cause: error, safeMessage: error.message);
    }
    if (error is VaultDriverFailure) {
      final code = _mapDriver(error.code);
      return PersistenceError(code, cause: error, safeMessage: error.code);
    }
    if (error is ArgumentError) {
      return PersistenceError(PersistenceErrorCode.invalidArgument,
          cause: error, safeMessage: error.toString());
    }
    return PersistenceError(PersistenceErrorCode.internalAdapterFailure,
        cause: error);
  }
}
```

映射器是**纯 Dart**、无副作用、无 I/O，方便在 `inMemoryDemo` 与 `sqliteEncrypted` 下跑同一套单元测试。

### 5. 调用方义务

`runtime_coordinator` / `recovery` / `sync_worker` / UI controller（`apps/personal_os_app/lib/src/controller/app_controller.dart`）必须：

1. 不再直接 `catch VaultSchemaViolation` 或 `catch EventAppendConflict`；改为 `catch Object` 后调用 `PersistenceErrorMapper.map(error)` 转成 `PersistenceError`；
2. 对外暴露的 `errorCode` 取 `persistenceError.code.wireValue`，不再传 `result.reasonCode` 等内部字符串；
3. UI 层错误显示只信任 `safeMessage`，不显示 `cause.toString()`；
4. evidence ledger 记录 `wireValue` 与 `safeMessage`，不记录 `cause`、不记录 `stackTrace`。

### 6. 与 ADR-0010 evidence ledger 的接口

`evidence/android/tool/validate_evidence.py` 与 `evidence_writer.py` 已经有一套 `forbidden_keys` 列表（`raw_log`、`secret`、`key_material`、`system_fingerprint` 等）。本 ADR 与之对齐：

- evidence 记录失败时，`error.code` 字段记录 `wireValue`（如 `persistence.d4_persistence_forbidden`）；
- evidence 记录 `error.safe_message` 字段记录 `safeMessage`；
- evidence **禁止**记录 `error.cause`、`error.stack_trace`、原始异常的 `toString()`；
- `validate_evidence.py` 增加规则：若 evidence 中的 `error.cause` 或 `error.stack_trace` 非空，校验失败。

### 7. 不变量

1. **稳定 wire value**：`PersistenceErrorCode.wireValue` 一旦发布，**禁止**改语义；只能新增或废弃（标 `deprecated`）。
2. **失败闭合（fail closed）**：未分类的失败一律归 `internalAdapterFailure`，**禁止**抛裸 `StateError` 或 `Exception` 到调用方。
3. **D4 永远拒绝**：`d4PersistenceForbidden` 是不可绕过的拒绝码，与 ADR-0013 §3 一致；任何 adapter 配置、consent、purpose 都不能解除。
4. **日志安全**：`safeMessage` 必须可被 `validate_evidence.py` 走查不命中 `forbidden_keys`；任何包含路径、密钥、设备指纹的字符串不能进 `safeMessage`。
5. **跨适配器一致**：相同输入（D4 blob、revision 冲突、解锁过期等）在 `inMemoryDemo` / `sqliteEncrypted` / 未来 Windows / iOS 适配器下必须产生相同的 `wireValue`。

## 理由

1. **避免散点 catch**：当前调用方要 catch 多个内部类型，映射器把“知道内部类型”集中到一个纯 Dart 类，上层只学一种 `PersistenceError`。
2. **机器可解析**：`wireValue` 枚举与 `SecurityErrorCode.wireValue` 同形态，evidence ledger、CI 校验、跨端日志聚合都能直接按字符串聚合。
3. **不破坏现有测试**：内部异常类不被立刻删除，映射器在边界出口使用，旧测试可以继续 catch `EventAppendConflict`。
4. **跨平台准备**：Windows DPAPI、iOS Keychain 落地时只需把平台异常接到 `internalAdapterFailure` 或新增一个细分码，无需重写调用方。
5. **安全事件可审计**：把 `safeMessage` 与 `cause` 分开，evidence 只记录前者，审计链不泄露密钥或路径。

## 影响

- **正面**：
  - 调用方代码简化：`catch Object => PersistenceErrorMapper.map(error)`；
  - evidence ledger 的 error 字段稳定，跨适配器可比较；
  - ADR-0013 §7 留下的“错误码归一”开放问题被本 ADR 解决。
- **负面 / 成本**：
  - 现有 `InMemoryEventStore.appendAll` 抛裸 `StateError` 需要改为 `PersistenceError(eventAppendRejected, ...)`，会破坏任何 catch `StateError` 的测试；M2 内必须先扫描调用方；
  - 需要在 `runtime_coordinator`、`recovery`、`sync_worker`、`app_controller` 出口加映射器调用，4 处接缝点；
  - `PersistenceErrorMapper` 需要被 ADR-0008 composition root 校验：禁止 UI 直接 import 适配器内部异常类型，只能 import `storage_api` 的 `PersistenceError` 与 `PersistenceErrorMapper`；
  - `validate_evidence.py` 需要扩展规则，校验 `error.cause` / `error.stack_trace` 不出现在 evidence；
  - 现有 `app_controller.dart` 的 `_errorCode = 'unexpected_failure'` 字符串需要替换为 `wireValue`，UI 测试可能要同步更新断言。
- **向后兼容**：内部异常类型保留至少一个 minor 版本，便于迁移；最终在 ADR-0014 v2 中可以全部替换为 `PersistenceError`。

## 未解决问题

1. **HTTP/Relay 错误**：`in_memory_relay` 与未来真实 Relay 适配器抛的网络错误是否进同一份 `PersistenceErrorCode`，还是单独建 `TransportErrorCode`？建议先归 `internalAdapterFailure`，等真实 Relay 落地时再补细分码。
2. **`cause` 序列化策略**：是否定义 `cause` 的稳定 `wireValue` 以便 evidence ledger 记录“内部异常类型”而不泄露内容？候选：`cause_type` 字段记录类名，`cause_message` 不记录。M2 决定。
3. **跨语言映射**：Windows / iOS 原生异常如何映射？建议在 MethodChannel 边界把 native code 翻成 `wireValue` 后再 wrap 进 `PersistenceError`，避免 Dart 层 catch 平台异常。
4. **重试策略**：`providerUnavailable` 与 `vaultLifecycleInvalid` 是否要附加 `retryable: bool` 字段？M2 先不加，由调用方按 `wireValue` 自行决定。
5. **`PersistenceError` 是否实现 `Error` 而非 `Exception`**：当前选择 `Exception`，便于 catch；若未来需要不可恢复语义，可单独加 `PersistenceFatal`。

## 验证计划

M2 退出前必须满足：

- `packages/storage_api/lib/src/persistence_error.dart` 实现 `PersistenceError` + `PersistenceErrorCode` + `PersistenceErrorMapper`，含稳定 wire value 表；
- 单元测试覆盖每个 `PersistenceErrorCode` 至少一条映射路径（≥ 17 个 case）；
- `runtime_coordinator`、`recovery`、`sync_worker` 出口通过 `PersistenceErrorMapper.map` 转换；
- `app_controller.dart` 的 `errorCode` 字段返回 `wireValue`，单元测试断言稳定码；
- `validate_evidence.py` 增加 `error.cause` / `error.stack_trace` 禁入规则，并提供 fixture 测试；
- 至少一条 evidence 记录证明 D4 在 `BlobStore.put` 与 `EventStore.appendAll` 下都映射到 `persistence.d4_persistence_forbidden`，跨适配器一致；
- 至少一条 evidence 记录证明 `VaultDriver.unlock` 失败映射到 `persistence.vault_unlock_failed`。

未完成上述验证前不得宣称生产模式可用。

## 后续候选

- ADR-0014 v2：内部异常类型全部替换为 `PersistenceError`，删除 `EventAppendConflict` / `VaultSchemaViolation`；
- `TransportErrorCode` ADR：覆盖 Relay / Sync 网络层错误；
- `cause_type` 字段：稳定记录内部异常类型，方便跨端日志聚合；
- `retryable` 字段：在 `PersistenceError` 上加可重试标记；
- 跨平台映射 ADR：Windows DPAPI / iOS Keychain / Linux libsecret 的 native-to-Dart 错误映射策略。
