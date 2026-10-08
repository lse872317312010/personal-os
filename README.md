# Personal OS

一个Android-first、Agent-agnostic的个人策略资产与反馈闭环系统。

应用的能力由用户选择的 GPT 或其他外部 Agent 提供；Personal OS 保存结构化个人资料和连续历史，让常用 Agent 能基于这些数据继续规划和复盘。当前优先打通整套闭环，并在 Web 展示操作流程，随后验证 Android 真机。见[优先级决策 0016](docs/decisions/0016-agent-access-and-web-loop-first.md)。

当前聚焦 Web 浏览器内的真实可用性和自动 Agent 闭环。Windows/Linux 启动包维护、Android 真机与两端同步后排；桌面包不再自动构建发布。见[Web 验证决策 0019](docs/decisions/0019-web-validation-only.md)。

Personal OS保存个人已有资产、当前状态、目标、约束、策略、计划、执行、确定性结果和主观反馈。Codex或其他外部Agent/Harness通过MCP读取并维护这些数据，负责全部分析、推理、策略生成和复盘；Android App不内置特定模型，负责权威数据、执行监督和历史连续性。

## 自动 Agent Web 闭环

[既有公开入口](https://lse872317312010.github.io/personal-os/) · [历史启动包（暂停维护）](https://github.com/lse872317312010/personal-os/releases/tag/automatic-agent-web)

当前直接验证编译后的浏览器应用，测试服务由 Node 启动，不依赖 Windows 批处理或桌面启动包。CI 覆盖 390×844 和 1440×900 两种浏览器尺寸，从页面内填写 Agent 连接开始，完成计划、反馈、复盘及刷新恢复。网关仍承担凭据和历史存储；公开静态入口尚不是可独立调用 AI 的线上应用。

首次使用 **Continue with ChatGPT** 登录并授权；后续请求和回复在应用内自动完成，无需复制提示词、粘贴回复或导入 JSON。桌面启动脚本已保留，但其启动问题暂不作为 Web 验证任务处理。

保存目标和现状 → 自动生成行动计划 → 用户确认并执行 → 记录结果 → 自动复盘 → 用户接受复盘 → 自动生成下一轮。行动卡在首屏，目标、连接设置和历史按需展开。结构化资料和事件历史加密保存在本机服务中，刷新或重启后可以接续；请求 AI 时会向所选服务发送当前上下文。

展开 AI 连接，点击“接入其他 AI”，填写服务地址、模型和必要的密钥即可使用 Responses、OpenAI 兼容 API 或 HTTP Agent。连接加密保存在本机，可随时选择和编辑；切换 Agent 或删除连接保留目标与行动历史，下一次复盘继续带上已有结果。日常接入不需要设置环境变量。

“测试 AI 连接”发送固定测试内容，确认模型能否响应；不会读取个人资料或创建行动记录，服务可能计入用量。已保存的目标与个人条件、行动历史分别在折叠卡片中查看。正式计划仍需校验和用户确认。

接入方法与数据边界见[自动接入说明](docs/automatic-agent.md)，当前优先级见[决策 0017](docs/decisions/0017-automatic-agent-local-web.md)。公开站点提供下载，实际应用在本机运行。测试使用明确的模型替身；真实 ChatGPT 推理仍需实际合资格账号授权，不构成 Android 真机或真实效果验收。

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

- 最终设备 MVP 保留 Android；当前按用户要求优先交付自动 Agent 本机 Web 闭环；
- Redmi Turbo是首个Primary Vault和dogfood设备；
- Flutter UI + Dart-first core继续保留；
- Android Vault 的权威边界继续适用；本机 Web 的独立加密事件存储不冒充 Android Vault，也未实现两端同步；
- 推理元交互完全交给外部Agent/Harness；
- MCP是首选在线接口；
- JSON/JSONL Context与Proposal Bundle是兼容和退出接口；
- UI、MCP和文件导入共享同一Application API；
- Agent可以维护资产、创建策略、计划和复盘，但不能篡改历史；
- 原生 Windows 客户端、Windows/Linux 启动包维护、多设备同步、内置模型、多Agent编排和高级披露暂缓；当前直接验证 Web 页面及其网关。

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
- 自动 Agent 网关、ChatGPT 授权、通用模型适配、单页行动卡及本机历史恢复；
- Android两轮Strategy UI、Harness身份绑定、handoff与冷启动恢复；
- 可验证无损事件归档和口令加密的Android备份/原子恢复；
- 构建、测试、APK SHA-256和provenance链。

这些代码是新方向的重要基础。现有 Android 内置 OpenAI 路径、原生 Windows spike 和多设备同步不属于当前 MVP 主线；本机 Web 自动接入沿用共享策略协议和 Application API。

## 当前状态

外部Agent策略主链已进入设备与真实使用验证阶段：

- 本机 Web 入口已自动发送上下文、接收计划/复盘/下一轮，并持久保存连续历史；真实账号推理仍待首次授权验收；
- 领域、事件、SQLite projection、Application authority与Agent Protocol v0已经落地；
- Context、Proposal和Review Bundle使用同一厂商无关协议，并已验证两个Harness的历史接续；
- Android可完成策略提案确认、执行/结果记录、结构化复盘、Strategy v2谱系展示和冷启动恢复；
- 加密备份支持错误口令/篡改拒绝、原子恢复和恢复后强制重锁；
- G0–G2由仓库CI验证；G3必须在Redmi真机执行规范九场景；
- MCP 2025-06-18 JSON-RPC适配与逐调用capability校验已实现，但Android前台网络监听仍未开启；
- 同一Goal的2–6周真实两轮dogfood尚未完成；
- 在G3与G4真实证据齐备前，项目不能宣称 `DOGFOOD_READY`。

## 文档入口

- [自动 Agent 接入与启动](docs/automatic-agent.md)
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
