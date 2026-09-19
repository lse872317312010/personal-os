# Changelog

## 2026-09-19 — MCP adapter authority hardening

### Added

- MCP 2025-06-18 JSON-RPC handshake, tool discovery and six-tool dispatch adapter;
- volatile Harness binding, server-owned Session revision and explicit `revokeAll()`;
- Android foreground MCP transport security contract.

### Hardened

- every context read, object read, proposal and review now rechecks its granted capability;
- proposal/review/close reject closed or failed durable Agent sessions;
- Harness/profile mismatches return stable `access_denied`;
- transport failures never return raw exception text, paths, keys or user content.

### Not Yet Enabled

- no Android socket, HTTP listener, LAN binding or background service is enabled;
- live MCP remains unavailable until lifecycle, bearer, body-bound and loopback Android tests pass.

## 2026-09-15 — Android external-agent strategy loop

### Accepted

- MVP只保留Android，Redmi Turbo继续作为Primary Vault和dogfooding设备；
- Personal OS保存个人资产、目标、策略、执行、结果和复盘；
- 推理完全由Codex或其他外部Agent/Harness承担；
- MCP作为首选在线接口，JSON/JSONL Bundle作为离线兼容接口；
- MVP必须完成同一Goal的Strategy v1与v2两轮真实迭代；
- 更换Agent后必须能够延续同一历史。

### Changed

- App内模型分析从MVP主线移除；
- Model Gateway方向调整为Agent Gateway；
- Strategy、Execution、Outcome、Review和AgentSession成为核心建模对象；
- UI、MCP和Bundle统一经过Application Commands/Queries；
- M2/M3验证门改为Android Vault、MCP兼容和两轮策略闭环。

### Deferred

- Android内置OpenAI Responses调用；
- Windows客户端和secure adapter；
- 多设备E2EE、Relay与Restricted Collector；
- 多Agent编排、自动模型选择、渐进披露和个人模型训练。

### Preserved

- Dart-first core、EventStore、Policy、SQLCipher、Keystore、Encrypted Blob、任务反馈、导出恢复和APK provenance继续作为新方向基础。

## 2026-08-24 — Mobile MVP theme preference

- Added volatile in-memory system/light/dark theme selection; it resets on process restart.
- No persistence, platform permission, or sensitive-data access is involved.

记录项目基线、范围、需求和决策的实质变化。项目尚未进入发布版本阶段。

## 2026-08-20 — Coding Wave 10

### Added

- 中文手机 MVP：授权、建议、计划、行动、反馈与复盘完整引导；
- 完整 Android Gradle host、跨 Windows/WSL 构建与 Redmi 安装脚本；
- STATIC→TEST→BUILD→DEVICE→DOGFOOD 五级可用性验收门；
- 完整 journey、流程门控与验收审计 tests。

### Hardened

- 计划未确认不能执行任务，任务未反馈不能创建复盘；
- Manifest 零敏感权限、禁用 backup 与 cleartext；
- Release signing 不使用 debug key，仓库不存签名秘密；
- Synthetic evidence 永远不能产生已验证结论。

### Pending

- GitHub Actions 构建首个 debug APK；
- Redmi Turbo 真机九场景与真实周期 dogfood。

## 2026-08-20 — Coding Wave 9

### Added

- Vault/EventStore/Model/Sync 的 fail-closed runtime coordinator；
- 恢复协议与 fixtures 的 dependency-free 一致性审计；
- Redmi Turbo 九场景真机 runbook 与严格非敏感 evidence schema；
- 独立 Repository Contracts CI。

### Verified

- 恢复审计真实执行通过，Python tests 8/8；
- Android synthetic evidence、SQLite schema、依赖图和 shell syntax 通过。

### Pending

- Runtime Dart tests 与 Redmi Turbo 九场景仍待有工具链/设备的环境执行。

## 2026-08-20 — Coding Wave 8

### Added

- Security-state-first 的纯 Dart recovery orchestrator；
- opaque key lease 的 SQLite/SQLCipher driver lifecycle contract；
- Android-first、跨平台可替换的 device security bridge；
- M2 真机/跨平台验证矩阵与本地 package dependency gate。

### Hardened

- Relay 外层恢复 envelope 不暴露 generation/status；
- native bridge 任意异常都转换为稳定脱敏错误；
- 恢复成功前严格执行撤销、epoch、tombstone 和一致性门禁。

### Not Yet Verified

- 新增 28 项 Dart tests 因环境无 Dart SDK 尚未实际执行；
- contract 不等于真实 SQLCipher、Keystore、StrongBox 或生物认证实现。

## 2026-08-20 — Coding Wave 7

### Added

- Driver-neutral SQLite EventStore，原子写入事件、投影和 outbox；
- subject revision 无损索引、精确事件幂等和 collision 检测；
- 流式密文 Blob engine、失败清理、crypto-erasure 与安全日志边界；
- Recovery Protocol v1、12 组语言中立 fixtures 与恢复测试契约。

### Verified

- SQLite schema v1 在内存 SQLite 上迁移、约束和触发器验证通过；
- JSON fixtures、shell 脚本语法和 whitespace 检查通过。

### Not Yet Verified

- 当前环境缺少 Dart/Flutter SDK，新增 Dart tests 尚未实际执行；
- SQLCipher、Android Keystore、Redmi Turbo 真机与 Windows 互操作仍是 M2 硬门禁。

## 2026-08-20 — Coding Wave 6

### Added

- Flutter Task/Review 的真实 Application 事件闭环；
- EventEnvelope/Projection 严格稳定 JSON codec 与深层不可变数据；
- 账户隔离、密文专用的 In-memory Relay；
- 可信设备 SyncWorker、AAD 验证、ACK 校验与明文 buffer 清理；
- Release 模式仍生效的 Revision、SchemaVersion 与 ActorRef 不变量。

### Hardened

- Relay cursor 与 envelope 幂等均绑定 account pseudonym；
- SyncPort 不暴露业务 EventEnvelope；
- D4 在 codec、sync worker、application、store 与 schema 多层拒绝。

## 2026-08-20 — Coding Wave 4–5

### Added

- Task 完成/跳过与 Review 接受/拒绝的完整反馈用例；
- SQLite Vault schema v1、迁移和可执行 SQLite smoke validator；
- 独立 synthetic model fixture adapter；
- 流式 BlobStore、删除语义与受限 metadata；
- 仅传输密文 envelope 的 Relay Sync API。

### Hardened

- Application、In-memory Store 和 SQLite 三层拒绝 D4；
- 删除 tombstone 使用不可关联随机 token，不保存目标哈希；
- Tombstone 传播状态改为 append-only log；
- Flutter UI 不再定义模型结论；Relay adapter 不再接触 EventEnvelope 明文。

## 2026-08-20 — Coding Wave 3

### Added

- 覆盖 S1–S4 事件词汇的扩展 reducer、删除 barrier 和 Conflict 生命周期；
- Android-first Flutter shell 与 Android CI；
- 精确 revision 的 in-memory Consent repository；
- 平台无关 VaultSession、UnlockGrant、KeyProvider 和设备撤销接口。

### Corrected

- 删除 Flutter demo 的本地假授权，改由真实 Policy adapter 二次失败关闭；
- Android host 不完整时只在 CI 临时副本补全，避免生成器覆盖源码。

### Blocked

- GitHub 连接写入额度暂时耗尽，Wave 2/3 等待恢复后同步；本地代码不等同于远端完成。

## 2026-08-20 — Coding Wave 2

### Added

- 外貌分析 Application → Policy Core 真实 fail-closed adapter；
- S1–S4 JSON fixture 的纯 Dart runner、稳定机器输出和明确 unsupported 语义；
- 根级 Dart 检查脚本与 GitHub Actions Core 门禁；
- 13 个 adapter/runner 测试，累计 30 个 Dart test cases。

### Hardened

- 外貌分析只能使用固定 `appearance_review / portrait / derive / D3` scope；
- Consent 必须唯一且绑定具体 revision，repository/clock 异常默认拒绝；
- contract runner 禁止输出 payload，并在持久化前拒绝 D4。

## 2026-08-20 — Coding Wave 1

### Added

- Policy package：D4 硬拒绝、敏感度继承、Consent 全范围校验和 R0–R4 风险判定；
- Application、Storage、Model Gateway 和 Sync 的平台无关 ports；
- 外貌分析最小闭环用例与 fake-port 测试；
- 实现正式 EventStore port 的原子 in-memory adapter；
- 17 个 Dart 测试案例和 Wave 1 集成评审。

### Corrected

- 主审发现并修正 R3 初稿：MVP 即使得到用户确认也不得执行外部动作，只能产生草案。

### Pending

- 环境缺少 Dart/Flutter SDK，编译、analyze 与测试执行证据仍待补齐。

## 2026-08-20 — 首批多智能体并行编码

### Added

- 多智能体文件所有权、开发波次与 G0–G7 集成门禁；
- 纯 Dart `domain` 与 `events` package 骨架；
- 事件信封、首批事件类型和最小确定性 reducer；
- S1–S4 机器可读 JSON fixtures 与 39 条契约测试 manifest。

### Verified

- JSON fixtures 可解析，事件与预期结果数量一致；
- `git diff --check` 通过，core 未引入 Flutter import。

### Not Yet Verified

- 当前环境缺少 Dart/Flutter 工具链，尚未完成编译、analyze 和自动化测试；
- Redmi Turbo 真机、SQLCipher/Keystore 与 Windows 构建仍待后续门禁。

## 2026-08-20 — M2 Spike 与安全协议设计

### Added

- Flutter/Tauri 共用的垂直 Spike 范围、测量指标和淘汰条件；
- 客户端 Safety Gates 与加权评分表；
- E2EE 设备同步 envelope、gap detection、补采、撤销和 Restricted Collector 规则；
- 设备、Vault、Blob、Account Epoch 与恢复密钥层级草案；
- 使用 M1 S1–S4 完成推荐架构第一轮走查。

### Blocked

- 当前执行环境缺少 Flutter/Dart/Rust/SQLite 工具链，因此尚未把 Spike 标记为实际通过。

## 2026-08-20 — M2 架构原则与候选比较

### Accepted

- local-authoritative encrypted hybrid 架构原则；
- 主设备持有完整 Vault，Restricted Collector 不持有完整投影；
- 云端中继不拥有 D2/D3 业务明文解密能力。

### Added

- M2 架构约束、客户端/数据层候选比较、推荐逻辑架构；
- 初版威胁模型和官方技术调研来源；
- Decision 0003 记录本地权威混合架构。

### Deferred

- Flutter 与 Tauri、Dart 与 Rust 的最终选择；
- 具体同步协议、密钥恢复和供应商选择。

## 2026-08-20 — M1 完成

### Accepted

- Core Data Model、Event Log、状态机、授权、删除、快照与契约测试 v0.1；
- 显式并发冲突语义，拒绝静默 last-write-wins；
- Schema、事件和投影的独立演进规则；
- 字段级敏感度和派生数据继承规则。

### Added

- M1 退出评审与对 M2 的硬约束；
- M2 技术选型启动问题、决策顺序和候选方案提交要求。

### Changed

- 项目状态切换为 M2 Ready；
- 核心数据模型、事件日志和契约测试状态改为 accepted。

## 2026-08-20 — M1 契约展开

### Added

- Claim、Goal、Plan、Task、Consent 和 Review 的显式状态机；
- Actor、Capability、ConsentRef 和授权决策规则；
- 基线到计划、反馈修订、撤销删除、重复迟到事件等示例序列；
- L0–L3 删除层级、tombstone、引用、Snapshot 和压缩语义；
- 覆盖确定性、状态、时间、授权、删除和端到端场景的契约测试清单。

### Updated

- 核心数据模型与事件日志加入配套规范链接；
- M1 Roadmap 仅剩并发/Schema/敏感度审查和退出评审。

## 2026-08-20 — M0 退出并进入 M1

### Accepted

- M0 产品章程、MVP 范围、核心概念、验收标准和隐私保守规则；
- 首个 MVP 采用“最小分析能力 + 完整行动反馈闭环”；
- M1 正式定义为 Core Data Model & Event Log。

### Added

- M0 退出评审与已知证据债务；
- MVP v0.1 冻结范围和验收标准；
- 核心数据模型 v0.1 草案；
- append-only 事件日志契约 v0.1 草案；
- Decision 0002 记录 MVP 纵向切片选择。

### Changed

- MVP 范围冻结归入 M0，M1 转为核心数据模型与事件日志；
- 项目状态切换为 M1 In Progress。

## 2026-08-20 — 领域展开与风险控制

### Added

- 将健身、饮食和关系模块扩展为可追踪的候选需求闭环；
- 建立 R0–R4 行动风险等级、领域控制矩阵和人工确认要素；
- 建立结合痛点、闭环贡献、证据、可验证性、负担和风险的优先级方法；
- 将新增领域需求纳入追踪矩阵。

### Clarified

- 数据敏感度与行动风险是两条独立轴；
- 高分需求不能越过安全硬约束；
- 原始证据不足时不进行看似精确的需求评分。

## 2026-08-20 — 场景与追踪体系

### Added

- 建立 5 个端到端用户场景：基线、机会排序、行动计划、复盘校准和跨域冲突；
- 建立技术无关的领域概念模型、生命周期与不变量；
- 建立北极星目标、用户场景、候选需求、风险和决策之间的追踪矩阵；
- 建立统一术语表，减少需求阶段的概念漂移。

### Updated

- 为 M0 增加可核验的进度清单和剩余退出条件；
- README 增加场景、领域模型、追踪矩阵与术语入口。

## 2026-08-20 — M0 基线扩展

### Added

- 建立项目章程，明确使命、核心问题、当前范围、成功标准和治理方式；
- 建立 `0.1-draft` 需求基线和证据等级；
- 建立系统、外形优化、关系和非功能候选需求；
- 建立 D0–D4 数据分类与处理规则草案；
- 建立决策记录目录，并接受“需求先于技术”决策。

### Clarified

- 当前仍处于 M0，所有功能需求均未冻结；
- 2026-08-17 原始对话尚未完整进入仓库，相关条目必须保留待核验标记；
- 外形优化是 MVP 候选入口，不是已作出的 MVP 决策。
# 2026-08-20 — M2 Android-first 平台决策

### Accepted

- Redmi Turbo / Android 作为首个 Primary Vault 与 dogfooding 真机；
- Flutter 作为跨平台主客户端，v1 采用与 Flutter UI 解耦的 Dart-first core；
- Windows 作为后续 Secondary Trusted Device，Tauri 与 Rust 改为有实证触发条件的候选。

### Added

- 手机优先的交互与发布顺序；
- 跨平台包边界、ports/adapters 依赖规则；
- Android 真机与 Windows vertical slice 的验证计划。
