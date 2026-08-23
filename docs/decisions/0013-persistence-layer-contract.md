# 0013 — 持久化层契约（Persistence Layer Contract）

日期：2026-08-23  
状态：proposed

## 背景

ADR-0003 锁定 local-authoritative encrypted hybrid 架构，ADR-0008 决定使用集中式 Composition Root 切换 `inMemoryDemo` / `sqliteEncrypted` 等运行模式。同一份领域/应用代码必须能在三种存储模式下保持相同行为：

- **`inMemoryDemo`**：进程内易失存储，演示与早期联调用；
- **`sqliteEncrypted`**：SQLCipher 加密本地存储，主生产模式；
- **`inMemoryPolicy` / `inMemoryRelay`**：策略、Relay 等附属能力的临时实现。

目前各接口（`EventStore`、`BlobStore`、`VaultDriver`、`KeyProvider`、`VaultSession`）已散布于 `packages/storage_api`、`packages/security_api` 与 `adapters/sqlite_vault_driver`。它们的实现位于 `adapters/in_memory`、`adapters/sqlite_vault`，且 `apps/personal_os_app/lib/src/composition/app_composition.dart` 是唯一组装点。在追加 SQLCipher 驱动、Blob 加密、跨端同步等真实实现前，需要一份契约明确以下不变量：

- 哪些接口属于持久化层；
- 不同模式下的适配器选择规则；
- D4 等敏感度如何在适配器入口被强制拒绝；
- 批量写入的事务保证；
- Vault 生命周期与 EventStore/BlobStore 调用顺序的关系；
- Composition Root 的禁入区。

不冻结契约就难以让多个 Wave 平行开发真实适配器，也难以让 `tool/check_composition_root.py` 长期守住边界。

## 决定

### 1. 持久化层接口范围

下列接口属于持久化层，禁止在 UI、Controller、Application 层直接引用其具体实现：

| 接口 | 所在包 | 职责 |
| --- | --- | --- |
| `EventStore` | `packages/storage_api/lib/src/event_store.dart` | 仅追加的事件日志（append-only），按 subject/id 读取 |
| `BlobStore` | `packages/storage_api/lib/src/blob_store.dart` | 流式加密二进制对象存储，强制敏感度校验 |
| `KeyProvider` | `packages/security_api/lib/src/key_provider.dart` | 非导出密钥的创建、包装、解包、轮换、撤销、销毁 |
| `SecureUnlockPort` | `packages/security_api/lib/src/secure_unlock_port.dart` | 申请短时授权（UnlockGrant） |
| `VaultSession` | `packages/security_api/lib/src/vault_session.dart` | Vault 解锁/锁定状态机，能力租赁 |
| `VaultDriver` 及其协作接口 `VaultKeyProvider` / `VaultPlatformOpener` / `VaultConnection` / `VaultTransaction` | `adapters/sqlite_vault_driver/lib/src/vault_driver.dart` | SQLCipher 加密库的生命周期与安全 PRAGMA、迁移、rekey |

Blob 加密、密文解码等内部细节（`packages/blob_engine`、`packages/sync_engine`）不属于本契约直接约束对象；它们通过上述接口使用持久化能力。

### 2. 适配器选择规则（Composition Root 专用）

| 模式 | EventStore | BlobStore | KeyProvider / VaultSession | VaultDriver |
| --- | --- | --- | --- | --- |
| `inMemoryDemo` | `InMemoryEventStore`（含 Projection/Outbox） | 暂用进程内 map（v1 演示，禁止写 D3+） | 进程内 stub，不要求真实密钥 | 不适用 |
| `sqliteEncrypted` | `SqliteVaultEventStore` 注入 `SqlExecutor` | SQLCipher 保护的 BlobStore 适配器（待建） | Android Keystore 适配器（`adapters/device_security`） | `VaultDriver` + native SQLCipher opener |
| `inMemoryPolicy` / `inMemoryRelay` | 各自的 in-memory 适配器，仅用于策略/Relay 测试 | 不参与 | 不参与 | 不参与 |

Composition Root 必须按运行模式一次性构造所有上述依赖，禁止在 Widget/Controller 中做 if/else 模式判断。

### 3. 敏感度强制（D4 拒绝）

D4（user_content / 不可持久化个人数据）必须在持久化层入口被拒绝，且不可被任何授权或适配器绕过：

- `BlobStore.put`：必须先调用 `validateBlobPersistenceSensitivity(sensitivity)`，否则抛 `BlobAccessDenied.d4PersistenceForbidden`；不返回 `BlobRef`，不留地址化部分 blob。
- `EventStore.appendAll`：对每条 `EventEnvelope` 校验 `event.sensitivity != Sensitivity.d4`。
  - `InMemoryEventStore.appendTransaction` 已通过 `AppendResult.rejected(reasonCode: 'd4_persistence_forbidden')` 实现。
  - `SqliteVaultEventStore._validate` 抛出 `VaultSchemaViolation('D4 cannot enter persistent storage')`。
- `BlobMetadata` 构造函数也会调用同一校验，避免被绕过。

### 4. 事务保证

- `EventStore.appendAll(List<EventEnvelope> events)`：
  - **原子性**：整个列表必须在一个事务内写入；任一事件冲突或不通过 reducer，整体失败，不得留下部分事件、投影、seen ID、sequence 或 outbox 条目。
  - **顺序性**：必须按列表顺序应用 reducer，使 sequence 与 outbox sequence 单调递增。
  - **幂等性**：批次内或与已存在记录冲突的相同 `eventId` 视为重复而非失败；不同 payload 的同 ID 必须抛 `EventAppendConflict`。
- `BlobStore.put`：失败时不得留下可寻址的 partial blob；适配器必须清理中间文件。
- `BlobStore.delete`：幂等，对不存在 ref 返回 `BlobDeleteResult.alreadyAbsent`。
- `VaultDriver`：
  - 安全 PRAGMA（`foreignKeysOn` / `secureDeleteOn` / `trustedSchemaOff`）必须在同一事务内写入，先于任何迁移；
  - `unlock` 失败时必须尽力关闭连接并销毁 key lease，状态回退到 `locked`；
  - `rekey` 失败时不得替换 `_activeKey`，新 lease 必须尽力销毁；
  - `lock` / `close` 为 best-effort 关闭，但必须清除连接和 key 引用。

### 5. Vault 生命周期与持久化调用的顺序

- `EventStore` / `BlobStore` 的写操作必须仅在 `VaultSession.state == unlocked` 且 `VaultDriver.state == unlocked` 时进行；适配器可通过 `requireGrant()` 在写入前取授权，过期则抛 `SecurityException(SecurityErrorCode.unlockExpired)`。
- `VaultDriver.unlock` 完成迁移后才能构造 `SqliteVaultEventStore`；Composition Root 在解锁成功前不得向 UI 返回 EventStore 句柄。
- `VaultDriver.rekey` 与正在进行的 `appendAll` 不可同时进行；驱动通过单连接 + 单事务串行化，应用层不需要加额外锁。

### 6. Composition Root 禁入区

UI、Controller、Application Use Case 层不得：

1. 直接 `import` 任何 `adapters/*` 或 `packages/storage_api` / `packages/security_api` 的具体实现类（仅可 import 接口所在包，且仅注入通过构造函数）；
2. 构造 `InMemoryEventStore`、`SqliteVaultEventStore`、`VaultDriver` 等具体实现；
3. 在业务逻辑里 if/else 切换存储模式；
4. 直接调用 SQL 或 native Keystore API。

边界由 `tool/check_composition_root.py`（ADR-0008）静态校验，并在 CI（`tool/check_contracts.sh`）中执行。Composition Root 是唯一允许同时 import 接口与实现的位置。

### 7. 接口稳定性

- 上述接口的方法签名、参数名、异常类型视为 v1 契约；新增可选参数可以，但移除或改语义必须在新的 ADR 中说明并标注 `supersedes`。
- 适配器内部细节（`SqlExecutor`、`SqlTransaction`、`VaultKeyLease`）不进入稳定性契约，可以随实现演进。

## 理由

1. **集中契约降低平行开发风险**：当前已有 `inMemoryDemo` 演示路径和 `SqliteVaultEventStore` 的纯 Dart 驱动实现。在 SQLCipher 驱动、Keystore 适配器、Blob 加密引擎等并发开发前固化接口，可避免多处返工。
2. **D4 拒绝由入口承担**：把敏感度校验放在 `EventStore` / `BlobStore` / `BlobMetadata` 入口，使上层不必各自实现；同时确保任何未来适配器无法绕过 ADR-0010 的隐私不变量。
3. **事务保证与 ADR-0010 一致**：append-only + 原子批次 + 幂等去重是 evidence ledger、跨记录哈希链、recovery 演练的共同前提。
4. **Vault 生命周期契约保护密钥**：明文密钥只存在于 `VaultKeyLease`，生命周期由 `VaultDriver` 管理；其它层只在 `VaultSession` 授予的时间窗内操作，避免 key 在锁屏后仍可被写入。
5. **静态边界校验成本极低**：`tool/check_composition_root.py` 已存在并接入 CI；本 ADR 明确禁入区后，校验可据此扩展规则而无需重新讨论。

## 影响

- **正面**：
  - Wave 20j 之后任何新增适配器（SQLCipher、Windows EDP、iOS Keychain 等）只需满足本契约即可被 Composition Root 切换；
  - UI 与持久化层解耦后，可在测试中替换为 `InMemoryEventStore` 而无需修改 Widget；
  - 审计、Recovery、Sync 等跨模块可统一依赖同一组接口。
- **负面 / 成本**：
  - 现有 `SqliteVaultEventStore._validate` 与 `InMemoryEventStore.appendTransaction` 在异常类型上不完全一致（`VaultSchemaViolation` vs `StateError`）；后续 Wave 需统一为 `EventAppendConflict` 或同等语义，避免调用方分支。
  - `BlobStore` 目前尚无真实加密实现，Composition Root 切换 `sqliteEncrypted` 时不能立即提供全部能力；ADR-0011 / ADR-0012 的 envelope 与 sync 契约部分依赖此缺口，需要在 Wave 21+ 补齐。
  - Composition Root 校验需要扩展规则以覆盖新接口（如 `BlobStore` 的实现类名集合），将产生额外维护工作。
  - 适配器内部仍可能在不同平台暴露不同错误码（`VaultDriverFailure` vs `SecurityException`）；本契约只约束接口，不约束错误转换，后续需要一份 error mapping 表。

## 未解决问题

1. **BlobStore 加密实现**：当前 BlobStore 接口已约束 D4 拒绝和 metadata 不泄露路径，但没有指定密文格式；是否复用 ADR-0011 的 export envelope 还是定义独立 blob ciphertext 容器，待 Wave 21 决定。
2. **跨平台 VaultDriver**：Android 之外的 `VaultPlatformOpener` 实现策略（Windows DPAPI、iOS Keychain）尚未决定；本契约先假设 Android-first，后续 ADR 补充。
3. **错误码归一**：见上节“负面 / 成本”；需要一份 mapping ADR 或并入 ADR-0013 v2。
4. **事务可见性 / 隔离级别**：`SqlExecutor.transaction` 的隔离级别未明示，依赖具体驱动；如果未来允许并发写入，需要在契约中显式要求 SERIALIZABLE 或 equivalent。
5. **多 Vault 实例**：本契约默认单一 Primary Vault，未约束 Secondary Trusted Device 同时挂载多 Vault 的命名与隔离策略；待 ADR-0005 实现推进时再补充。

## 验证计划

M2 退出前必须满足：

- `tool/check_composition_root.py` 扩展到检测 `BlobStore`、`VaultDriver`、`KeyProvider`、`VaultSession` 的禁入区违规；
- `adapters/in_memory` 与 `adapters/sqlite_vault` 同时通过 `packages/storage_api/test/blob_store_contract_test.dart` 的契约测试（其中 SQLCipher 实现由 Wave 21 补充）；
- 在 `evidence/android/records/` 中至少有一条记录证明 `EventStore.appendAll` 在 `inMemoryDemo` 与 `sqliteEncrypted` 下产生相同 sequence、相同 projection、相同 outbox；
- 至少一条 evidence 记录证明 `BlobStore.put` 对 D4 输入抛 `BlobAccessDenied.d4PersistenceForbidden` 且无 partial blob；
- 至少一条 evidence 记录证明 `VaultDriver.unlock` 失败后 `state` 回到 `locked` 且无残留 key lease。

未完成上述验证前不得宣称生产模式可用。

## 后续候选

- BlobStore 加密容器的独立 ADR；
- Windows / iOS VaultPlatformOpener 实现策略 ADR；
- 持久化错误码归一 ADR（或并入本 ADR v2）；
- 多 Vault 实例与命名空间 ADR（依赖 ADR-0005 落地进度）。
