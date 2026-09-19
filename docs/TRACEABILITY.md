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

| MVP能力 | 当前实现 |
|---|---|
| EventStore与Reducer | Strategy/Execution/Outcome/Review/AgentSession事件与确定性projection已实现 |
| PersonalAsset与Strategy生命周期 | 一等领域对象、revision和parent谱系已实现 |
| SQLCipher与Keystore | Android生产组合已实现，等待Redmi G3验证 |
| Encrypted Blob/Photo Picker/Camera | 受控资产输入已实现 |
| Agent Protocol | v0工具名、Session、Context/Proposal/Review Bundle已冻结并实现 |
| Application authority | Agent只可提案/复盘，用户确认执行和结果 |
| Harness可替换性 | 双Harness契约与handoff已由自动化测试覆盖 |
| 冷启动连续性 | 完整事件分页和活动策略恢复已实现 |
| 导出恢复 | 可验证事件归档与口令加密Android备份已实现 |
| OpenAI/Provider UI | 暂停并从MVP生产主线解绑 |
| Windows/Sync/Relay | 保留历史资产，移出当前MVP |
| APK/provenance链 | 已实现，G2可由CI验证 |

## 5. 当前断链

- Android前台临时MCP传输尚未实现；当前可用的是同Schema离线Bundle路径；
- Redmi exact-APK九场景尚未执行，不能声明 `DEVICE_VERIFIED`；
- 两个不同外部Harness尚未在真实Android端完成在线接续，自动化契约不能替代运行证据；
- 同一Goal的Strategy v1/v2两轮2–6周真实dogfood尚未执行；
- 用户价值、负担与隐私评价尚无真实G4证据；
- 因此当前上限是CI支持的 `BUILD_VERIFIED`，不是 `DOGFOOD_READY`。

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
