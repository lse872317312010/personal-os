# M2-B1 基线与执行结论

更新时间：2026-08-24

## 唯一基点

- 分支：`main`
- 当前候选提交：PR #38 head（GitHub exact commit 绑定后更新）
- 当前工作树：clean
- evidence ledger 仍未绑定本轮 exact commit；未经过完整门禁前，不得把它们当作已发布证据

旧 Wave 分支只能作为需求或失败实现的参考，禁止整体 cherry-pick。所有新 Agent 必须从唯一基点创建独立分支，并只修改任务声明的文件域。

## 当前状态

项目属于 `M2-B1 · Android Secure Local MVP` 的实现基线，但尚未通过编译、设备或生产存储门禁：

- 已有纯 Dart domain/events/application 包、in-memory EventStore 和 Flutter 中文离线合成闭环；
- 已有 adapter 边界、D4 拒绝、事件冲突和 evidence ledger 的基础防线；
- 默认 synthetic Composition 仍把解锁、Consent、分析结果、任务状态和复盘状态保存在进程内；secure 注入路径具备 opaque session 边界，并已接入 native durable Vault/event-store 实现，但尚未取得运行时验证；
- Android Keystore 用户认证 primitive、native SQLCipher 数据库与 event JSON 存储、secure Dart event-store/session coordinator 已接入 secure composition；这些是代码实现状态，不是运行时或生产验证结论；
- mobile shell 已提供 profile-scoped observation history UI；展示的是事件存储中的观察记录，不等于真实照片已导入或模型分析已完成；
- 当前环境没有 Dart、Flutter、Android SDK/Gradle 的可执行验证记录，因此上述 native/Dart 路径未编译、未运行集成测试，未取得 APK 或设备证据；
- 仍未完成真实照片 ingestion、加密 Blob adapter、冷启动/重启恢复演练和 Redmi Turbo 真机证据；因此当前版本不能升级为 `DOGFOOD_READY`。

## 本轮模拟 Agent 结果

### Agent A · baseline-truth

修正 README 与 M2 verification matrix 的过时状态，明确 synthetic、contract、real-device evidence 的边界。

### Agent B · session-read-model

新增 `AppearanceSessionQueryHandler` 和纯 Dart read-model 测试。它从 profile-scoped event stream 重建 claim、goal、plan、task、review 的可读状态，不读取 Controller 内存字段。

明确限制：当前 feedback use case 产生的事件没有 profile subject，因此本 read model 尚不能声称恢复任务完成和复盘状态；该缺口归入下一任务 `B1-03/B1-04`，不能通过 UI 状态推断补齐。

### Agent C · persistence-error-parity

新增 `PersistenceErrorCode`/`PersistenceException` 稳定边界。in-memory 与 SQLite 的 D4、冲突、schema 和事务失败现在都保留兼容类型判断，同时提供固定 code/safe message；SQLite 的底层读写异常不再把原始内容透传给应用层。该错误边界已通过纯 Dart 契约测试，但由于当前工作区没有 Dart SDK，尚未完成运行时 Dart 验证。

### B1-03 · controller-bootstrap

`AppController.bootstrap()` 已接入 composition root。解锁后会从 profile event stream 恢复 analysis/goal/plan/task 的骨架；查询失败只产生稳定的 `persistence.read_failed`，不会显示原始异常。Consent 不从历史 appearance 事件推断，仍然默认拒绝，等待 B1-04 的正式生命周期事件。

### B1-04 · consent-lifecycle

已加入 `ConsentLifecycleUseCase`、`consent.requested/granted/revoked` 事件、可重复授权的 reducer 转移，以及 `EventBackedConsentRevisionRepository`。撤销事件会覆盖 fallback grant；无法解析的匹配授权事件不会回退放行。当前仍是 in-memory composition，尚未证明冷启动后的真实加密持久化。

### B1-05 · android-vault-contract

已冻结 `SecureVaultPort` 与 `OpaqueVaultSession`：平台适配器以短期
`UnlockGrant` 打开 Vault，Dart 侧只能持有生命周期 capability，不获得
数据库路径、native alias、连接、key lease 或任何 key bytes。安全错误文案
现在按 `SecurityErrorCode` 固定生成，调用方不能注入原生异常文本。

本轮只有纯 Dart 契约和 fake 测试；没有实现 Android Keystore、SQLCipher 或
真实加密存储，因此不能升级任何真机或 encryption-at-rest 状态。

相关提交：`0eb835c`、`6a87ce1`、`2062714`、`c913bbe`。Dart/Flutter 工具链缺失，
契约测试已补齐但尚未运行。

### B1-06/B1-07 · native vault and secure composition

Android 原生侧已加入私有 MethodChannel、稳定错误映射、AndroidX
BiometricPrompt、Keystore user-authenticated HMAC ticket primitive，以及
native SQLCipher database/event JSON storage。Dart 侧已接入 secure event store
和 session coordinator；`openVault` 仍保持 fail-closed，不会降级到 plaintext
SQLite/in-memory Vault。默认 demo Composition 仍明确使用 synthetic/in-memory
adapter，secure path 必须显式选择。

相关提交：`2086bdc`、`03ff463`、`c913bbe`、`8990825`、`7600976`、`2062714`、`c35bd9e`、`c66842f`、`13e2b79`、`fdbc6af`、`5181b14`、`01fb014`、`0404112`、`06d937e`。

当前 native auth、native SQLCipher storage 和 secure Dart composition 只有代码/静态审查状态：本环境没有 Android SDK/Gradle/Dart/Flutter，尚未编译或运行集成测试，未验证 SQLCipher production behavior，也未运行模拟器或 Redmi 行为验证。

### Observation history UI

`eb2658a` 将 profile-scoped observation history 接入 mobile shell。它是对已有
事件的读取展示，不能证明照片、Blob 加密、真实模型分析或持久化恢复已经完成。

### 本轮新增的契约加固

- `ad7c52b`：删除 request/complete barrier、opaque tombstone 和逻辑引用校验；明确未实现物理 Blob/key/database 删除。
- `048c9ce`：冻结安全事件导出契约；D4、密钥、路径、URI、token、digest 和明文内容永久拒绝，尚未实现文件分享或真实加密导出。
- `7d3880f`：加强 SQLite schema 约束和禁止持久化字段检查；仍只是 SQLite schema contract，不代表 SQLCipher 已接通。
- `be29f7d`：in-memory EventStore 对齐稳定错误码、同 ID 异内容冲突和批次零副作用回滚。
- `54be66b`：Runtime 生命周期操作串行化，避免并发启动/解锁/锁定穿透中间状态。
- `c35bd9e`：App 组合根显式区分 synthetic demo 与 secure path，锁定后清理敏感状态并阻止过期异步结果回写。
- `c698a8d`：Android native skeleton 的 `openVault`/`authenticate` 保持 fail-closed，session registry 防重复注册并拒绝无效 close 参数。
- `241d429`：根级 evidence schema 或敏感字段错误会使全体 gate fail-closed，不能继续汇总成 verified/dogfood。

### B2 前置契约

- `92831e6`：冻结 `BlobIngestionContract`，先校验 Consent、D4 和 media type，再以 bounded stream 交给 `BlobStore`；超出大小上限只返回稳定错误，不提供明文或内存降级。
- `40c9bbe`：新增 `RecordObservationUseCase`，把已有 opaque `blob://` 引用记录为 profile-scoped observation 事件；强制 user actor、Consent、D3 上限和原子 append，不读取文件、不接触原始 bytes。
- `3a3a7a1`：Debug APK artifact 同时上传非敏感 provenance manifest，绑定 commit、workflow run、应用版本和 APK SHA-256。

这批提交只完成 B2 的数据与安全边界，不能表述为“已经导入照片”。真实 Photo Picker/Camera、加密 Blob adapter 和模型读取仍待平台实现。

### 后续契约加固

- Blob：强制 consent binding、媒体类型/UTC/key/长度校验、删除重试不重复销毁 key。
- Sync：页级原子 append、D4 拒绝、sequence/replay/page-limit 防护；仍未实现真实签名、加密和 relay。
- Recovery：严格状态推进、staged cleanup 错误、认证 buffer 清零；仍未冻结生产密码学套件。
- Evidence：所有 pass 必须绑定同一 exact commit，synthetic 不能提升为真实设备证据。

相关提交：`e0171f5`、`95cfcbd`、`c241126`、`be3b39f`。

## 下一波执行顺序

1. `B1-06 android-native-vault`：在 Android/Kotlin/Flutter 工具链可用后编译验证现有认证 primitive、native SQLCipher database 和 event JSON storage；补 native integration tests，禁止降级。
2. `B1-07 secure-composition`：在 exact commit 上运行 secure EventStore/session coordinator、锁定/解锁、错误路径和冷启动恢复验证；不能用静态审查替代结果。
3. `B1-08 redmi-evidence`：只对 exact commit 构建 APK 并执行九场景真机 runbook。
4. `B2 encrypted-ingestion`：在真实 Android 工具链可用后接入 Photo Picker/Camera → encrypted Blob adapter → 临时文件清理，再接真实本地模型；当前只完成 adapter-neutral contract。

当前阻塞：本执行环境没有 `dart`、`flutter` 或 Android SDK，因此 B1-06 只能先保留为待执行验证，不能生成可信 APK、Keystore、SQLCipher 或 Redmi 证据。

## 下一门禁 checklist

- [ ] 在 PR #38 合并后的 exact commit 绑定 Dart/Flutter/Android 工具链版本并完成 format/analyze/test。
- [ ] 编译 Android debug APK，并记录 artifact digest；未编译前不得称为 build verified。
- [ ] 运行 native authentication、SQLCipher database/event JSON storage 与 secure session/event-store integration tests；未运行前不得称为 SQLCipher verified 或 production verified。
- [ ] 在 Redmi Turbo 执行锁屏、重启、进程终止、权限拒绝和离线恢复 runbook；未取得逐项证据前不得称为 Redmi 或 dogfood verified。
- [ ] 补齐真实 Photo Picker/Camera、encrypted Blob 和冷启动 durable recovery 证据后，再评估 `DOGFOOD_READY`。

## 门禁

本地没有 Dart/Flutter SDK 时，只能报告静态审查结果；不能报告 Dart test、Flutter test、APK 或 Redmi 证据通过。任何 `PASS` 必须绑定候选 commit、工具链、命令和 artifact digest。
