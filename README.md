# Personal OS

一个Android-first、Agent-agnostic的个人策略资产与反馈闭环系统。

Personal OS保存个人已有资产、当前状态、目标、约束、策略、计划、执行、确定性结果和主观反馈。Codex或其他外部Agent/Harness通过MCP读取并维护这些数据，负责全部分析、推理、策略生成和复盘；Android App不内置特定模型，负责权威数据、执行监督和历史连续性。

## 核心闭环

个人资产与状态  
→ 目标与约束  
→ 外部Agent提出Strategy  
→ 用户接受Plan  
→ Android监督Task执行  
→ 保存Execution、Outcome和Feedback  
→ Agent生成Review  
→ 创建Strategy新版本。

产品的核心价值不是一次性AI分析，而是让第二轮策略明确利用第一轮真实结果，并且更换模型或Agent后仍能继续同一历史。

## 当前冻结决策

- MVP只保留Android；
- Redmi Turbo是首个Primary Vault和dogfooding设备；
- Flutter UI + Dart-first core继续保留；
- Android Vault是核心数据唯一权威端；
- 推理元交互完全交给外部Agent/Harness；
- MCP是首选在线接口；
- JSON/JSONL Context与Proposal Bundle是兼容和退出接口；
- UI、MCP和文件导入共享同一Application API；
- Agent可以维护资产、创建策略、计划和复盘，但不能篡改历史；
- Windows、多设备同步、内置模型、多Agent编排和高级披露暂缓。

## MVP目标

围绕一个真实Goal完成两轮策略迭代：

1. Android建立PersonalAsset、Goal和Constraint；
2. 外部Agent读取目标上下文；
3. Agent写入Strategy v1和有限周期Plan；
4. App监督执行并记录结果；
5. Agent读取第一轮历史，生成Review；
6. Agent创建Strategy v2；
7. App展示v1到v2变化和证据；
8. 第二种Agent可以不修改核心Schema继续历史；
9. 数据可以无损导出和恢复。

## 权威对象

- PersonalAsset
- Goal / Constraint
- Observation
- Strategy
- Plan / Task
- Execution
- Outcome
- Review
- Attachment / Blob
- AgentSession / AgentAudit

系统严格区分UserFact、Observation、DeterministicOutcome、SubjectiveFeedback、AgentInference、Recommendation和Unknown。

## 当前工程基线

项目已经拥有：

- append-only EventStore与确定性投影；
- Consent、敏感度、冲突、删除和Schema演进；
- Flutter Android Shell；
- Android Keystore primitive；
- native SQLCipher存储；
- Encrypted Blob；
- Photo Picker和Camera；
- Task、Execution、Outcome与结构化Review流程；
- PersonalAsset、Strategy、AgentSession领域对象与生命周期；
- 厂商无关Agent Protocol v0和固定revision Context/Proposal/Review Bundle；
- Android两轮Strategy UI、Harness身份绑定、handoff与冷启动恢复；
- 可验证无损事件归档和口令加密的Android备份/原子恢复；
- 构建、测试、APK SHA-256和provenance链。

这些代码是新方向的重要基础，但现有Android内置OpenAI路径、Windows spike和多设备同步不再属于当前MVP主线。代码处置必须在影响分析后完成。

## 当前状态

外部Agent策略主链已进入设备与真实使用验证阶段：

- 领域、事件、SQLite projection、Application authority与Agent Protocol v0已经落地；
- Context、Proposal和Review Bundle使用同一厂商无关协议，并已验证两个Harness的历史接续；
- Android可完成策略提案确认、执行/结果记录、结构化复盘、Strategy v2谱系展示和冷启动恢复；
- 加密备份支持错误口令/篡改拒绝、原子恢复和恢复后强制重锁；
- G0–G2由仓库CI验证；G3必须在Redmi真机执行规范九场景；
- MCP 2025-06-18 JSON-RPC适配与逐调用capability校验已实现，但Android前台网络监听仍未开启；
- 同一Goal的2–6周真实两轮dogfood尚未完成；
- 在G3与G4真实证据齐备前，项目不能宣称 `DOGFOOD_READY`。

## 文档入口

- [项目章程](docs/PROJECT_CHARTER.md)
- [产品原则](docs/PRODUCT_PRINCIPLES.md)
- [MVP范围](docs/MVP_SCOPE.md)
- [需求基线](docs/REQUIREMENTS.md)
- [端到端场景](docs/USE_CASES.md)
- [验收标准](docs/ACCEPTANCE_CRITERIA.md)
- [路线图](docs/ROADMAP.md)
- [数据规则](docs/DATA_POLICY.md)
- [需求追踪](docs/TRACEABILITY.md)
- [推荐架构](architecture/PROPOSED_ARCHITECTURE.md)
- [平台策略](architecture/PLATFORM_STRATEGY.md)
- [架构约束](architecture/ARCHITECTURE_REQUIREMENTS.md)
- [M1核心数据模型](specs/CORE_DATA_MODEL.md)
- [M1事件日志](specs/EVENT_LOG.md)
- [变更记录](CHANGELOG.md)
