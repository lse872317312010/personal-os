# 需求追踪矩阵

状态：Android Agent-driven MVP baseline

## 1. 北极星能力到场景

| 北极星能力 | 场景 | 需求 |
|---|---|---|
| 保存个人资产与目标 | UC-01 | SYS-001、SYS-002、AND-001 |
| 外部Agent读取上下文 | UC-02 | AGT-001、AGT-002、AGT-005 |
| Agent维护资产 | UC-03 | AGT-003、AGT-004、AGT-006 |
| Agent生成策略和计划 | UC-04 | STR-001～STR-004 |
| App监督真实执行 | UC-05 | STR-005、STR-006、AND-004 |
| Agent复盘并修订策略 | UC-06 | STR-007～STR-009、AND-006 |
| 更换Agent继续历史 | UC-07 | AGT-007、NFR-006 |
| 导出与恢复 | UC-08 | SYS-006、AGT-008、AND-008 |

## 2. MVP主链

| 阶段 | 输入 | 权威写入 | 验收 |
|---|---|---|---|
| 建立上下文 | 用户资产、状态、目标、约束 | PersonalAsset、Goal、Observation | AC-001～006 |
| Agent连接 | 解锁Vault、Session | AgentSession/Audit | AC-101～109 |
| 策略生成 | 目标上下文 | Strategy v1、Plan | AC-201～205 |
| 执行监督 | Active Plan | Execution、Outcome、Feedback | AC-301～305 |
| 复盘 | v1全部证据 | Review、Strategy v2 | AC-306～307、AC-206～207 |
| 连续性 | 新Agent | 兼容Strategy新版本 | AC-108 |
| 数据主权 | 全部权威事件 | Export/Restore | AC-407 |

## 3. 需求到主要组件

| 需求组 | Domain/Event | Application | Android UI | MCP/Bundle | Storage |
|---|---:|---:|---:|---:|---:|
| SYS | 必需 | 必需 | 必需 | 部分 | 必需 |
| AGT | AgentRef/Session | 必需 | 连接管理 | 核心 | Audit |
| STR | 核心 | 核心 | 审核/监督 | 读写 | Event/Projection |
| AND | 部分 | 必需 | 核心 | 部分 | 必需 |
| NFR | 契约 | 边界 | 平台验证 | Schema | 可靠性 |

## 4. 当前实现映射

| 现有能力 | 新方向处理 |
|---|---|
| EventStore与Reducer | 保留并扩展Strategy/Outcome/Agent事件 |
| Claim/Goal/Plan/Task/Review | 保留，调整为Agent写入与App监督 |
| SQLCipher与Keystore | 保留 |
| Encrypted Blob/Photo Picker/Camera | 保留为资产输入 |
| Consent与Policy | 保留，简化为MVP Session权限 |
| AppearanceAnalysisGateway | 泛化或替换为Agent Gateway |
| OpenAI Responses Android Client | 暂停并从生产主线解绑 |
| Provider credential UI | 暂停 |
| Windows fail-closed spike | 保留历史，不继续 |
| Sync/Relay/Recovery协议 | 保留设计资产，移出MVP |
| APK/provenance链 | 保留 |

## 5. 当前断链

- PersonalAsset尚未成为明确一等实体；
- Strategy字段和状态机尚未按新目标冻结；
- Execution/Outcome/Feedback与Review的证据关系需补齐；
- AgentRef、AgentSession和AgentAudit尚未进入核心规范；
- MCP Resource/Tool Schema尚未冻结；
- Context/Proposal Bundle尚未冻结；
- Android实时MCP的连接方式尚未验证；
- 两个不同Agent延续同一历史尚未验证；
- 两轮真实策略dogfood尚未执行。

## 6. 延期项

以下不再属于当前追踪主链：

- Windows客户端；
- Android↔Windows同步；
- Relay；
- Restricted Collector；
- App内模型路由；
- 多Agent编排；
- 自动策略选择；
- 高级披露控制；
- 时态知识图谱；
- 个人模型训练。
