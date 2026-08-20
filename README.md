# Personal OS

一个长期演进的 **AI-native 个人决策操作系统**。

它不是单一的健身、饮食、外貌或社交 App，而是把个人目标、真实状态、约束、行动、反馈和长期记忆连接起来，持续帮助用户做出更好的决策。首位 dogfooding 用户是项目创建者本人，未来保留产品化与商业化可能。

## 当前阶段

项目已完成 **M0 产品章程与范围冻结**和 **M1 Core Data Model & Event Log**，正在推进 **M2 技术选型与总体架构**。已冻结 Redmi Turbo / Android 为首个 Primary Vault，并选择 Flutter + Dart-first core：手机先验证完整闭环，Windows 随后复用同一核心，平台能力通过 adapters 隔离。

## 首批领域

1. 健身与身体状态
2. 饮食与营养
3. 外形优化：护肤、发型、穿搭、体态与形象表达
4. 社交与关系优化

社交关系模块使用 `V × T × A × M` 漏斗作为分析框架：

- `V`：个人综合价值
- `T`：有效社交流量池
- `A`：可得性与接触机会
- `M`：双向匹配程度

所有关系设计仅面向成年人，并以合法、双方明确自愿、尊重边界为硬约束。

## 北极星目标

建立一个可信、可解释、可审计、可持续学习的个人决策闭环：

`感知现状 → 明确目标 → 识别差距 → 生成方案 → 执行动作 → 记录结果 → 复盘校准`

系统最终应当做到：

- 形成统一但可分域演进的个人状态模型；
- 把建议转化为可执行、可跟踪、可验证的任务；
- 通过长期反馈进行个性化，而不是只依赖一次性对话；
- 明确区分事实、用户输入、推断、建议与不确定性；
- 让用户始终拥有数据、权限和关键决策的控制权；
- 支持未来扩展到金融投资、职业资本、时间配置、消费与城市/区位选择。

## 近期交付目标

- 固化项目使命、范围、原则与非目标；
- 从 2026-08-17“男士外貌分析”对话提炼真实使用场景和决策链；
- 建立需求池、术语表、风险清单和验收标准；
- 选出一个最小纵向闭环作为 MVP，而不是同时开发所有模块；
- 在需求冻结后再进行技术选型、总体架构和模块接口设计。

## 文档入口

- [项目章程](docs/PROJECT_CHARTER.md)
- [M0 退出评审](docs/M0_EXIT_REVIEW.md)
- [MVP 冻结范围](docs/MVP_SCOPE.md)
- [MVP 验收标准](docs/ACCEPTANCE_CRITERIA.md)
- [发展路线与里程碑](docs/ROADMAP.md)
- [需求基线草案](docs/REQUIREMENTS.md)
- [端到端用户场景](docs/USE_CASES.md)
- [领域概念模型](docs/DOMAIN_MODEL.md)
- [需求追踪矩阵](docs/TRACEABILITY.md)
- [风险与人工确认矩阵](docs/RISK_CONTROL_MATRIX.md)
- [需求优先级方法](docs/PRIORITIZATION.md)
- [术语表](docs/GLOSSARY.md)
- [产品原则与边界](docs/PRODUCT_PRINCIPLES.md)
- [数据分类与处理规则](docs/DATA_POLICY.md)
- [需求提炼清单](docs/REQUIREMENTS_INBOX.md)
- [决策记录](docs/decisions/README.md)
- [M1 核心数据模型](specs/CORE_DATA_MODEL.md)
- [M1 事件日志契约](specs/EVENT_LOG.md)
- [M1 状态机](specs/STATE_MACHINES.md)
- [M1 授权模型](specs/AUTHORIZATION.md)
- [M1 示例事件序列](specs/EVENT_SEQUENCES.md)
- [M1 删除、快照与压缩](specs/RETENTION_AND_SNAPSHOTS.md)
- [M1 契约测试](specs/CONTRACT_TESTS.md)
- [M1 并发与冲突](specs/CONCURRENCY_AND_CONFLICTS.md)
- [M1 Schema 演进](specs/SCHEMA_EVOLUTION.md)
- [M1 敏感度继承](specs/SENSITIVITY_PROPAGATION.md)
- [M1 退出评审](docs/M1_EXIT_REVIEW.md)
- [M2 启动输入](docs/M2_KICKOFF.md)
- [M2 验证矩阵](docs/M2_VERIFICATION_MATRIX.md)
- [M2 架构约束](architecture/ARCHITECTURE_REQUIREMENTS.md)
- [M2 平台策略](architecture/PLATFORM_STRATEGY.md)
- [M2 逻辑包与依赖边界](architecture/LOGICAL_PACKAGE_LAYOUT.md)
- [多智能体并行开发计划](docs/MULTI_AGENT_CODING_PLAN.md)
- [M2 候选方案比较](architecture/OPTIONS.md)
- [M2 推荐逻辑架构](architecture/PROPOSED_ARCHITECTURE.md)
- [M2 威胁模型](architecture/THREAT_MODEL.md)
- [M2 技术调研来源](docs/research/M2_TECH_SOURCES.md)
- [客户端垂直 Spike 计划](architecture/CLIENT_SPIKE_PLAN.md)
- [客户端评分表](architecture/CLIENT_SCORECARD.md)
- [同步协议草案](architecture/SYNC_PROTOCOL.md)
- [密钥管理草案](architecture/KEY_MANAGEMENT.md)
- [恢复协议 v1](architecture/RECOVERY_PROTOCOL.md)
- [M1 架构走查](architecture/M1_ARCHITECTURE_WALKTHROUGH.md)
- [变更记录](CHANGELOG.md)

## 首批代码

- `packages/domain`：纯 Dart 核心值对象、Actor、敏感度和状态；
- `packages/events`：事件信封、事件目录与最小确定性 reducer；
- `fixtures`：S1–S4 跨语言 JSON 契约 fixtures；
- `test_contract`：CT-001–CT-504 测试 manifest 与证据状态。
- `packages/policy`：Consent、D4、敏感度继承和 R0–R4 失败关闭策略；
- `packages/application`：平台无关的外貌分析 command/query 与最小闭环；
- `adapters/in_memory`：原子事件、投影和 outbox 测试适配器。

本轮集成结论见 [Coding Wave 1 评审](docs/CODING_WAVE_1_REVIEW.md)。

后续已加入真实 Policy adapter、JSON contract runner 和 Dart Core CI，见 [Coding Wave 2 评审](docs/CODING_WAVE_2_REVIEW.md)。

Android Flutter shell、安全能力接口与扩展 reducer 的本地集成情况见 [Coding Wave 3 评审](docs/CODING_WAVE_3_REVIEW.md)。

完整反馈闭环、SQLite schema、Blob 和密文同步边界见 [Coding Wave 4–5 评审](docs/CODING_WAVE_4_5_REVIEW.md)。

Flutter 真实反馈链、严格事件 codec 与账户隔离同步模拟见 [Coding Wave 6 评审](docs/CODING_WAVE_6_REVIEW.md)。

事务型 SQLite EventStore、密文附件引擎与恢复协议测试资产见 [Coding Wave 7 评审](docs/CODING_WAVE_7_REVIEW.md)。

恢复状态机、Vault driver 与设备安全 bridge contract 见 [Coding Wave 8 评审](docs/CODING_WAVE_8_REVIEW.md)。

Runtime 编排、恢复契约 CI 与 Redmi Turbo 证据 runbook 见 [Coding Wave 9 评审](docs/CODING_WAVE_9_REVIEW.md)。

面向实际安装的中文离线闭环、Android 包装与 MVP 五级验收门见 [Coding Wave 10 评审](docs/CODING_WAVE_10_REVIEW.md)。

## 状态

`M2 In Progress / Android-first Flutter Architecture`
