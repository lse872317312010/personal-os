# 架构约束 v0.2

状态：accepted inputs

## 已确认约束

- MVP只保留Android；
- Redmi Turbo是Primary Vault与dogfooding设备；
- Personal OS保存个人资产、目标、策略、执行、结果和复盘；
- 推理完全由外部Agent/Harness承担；
- App不直接绑定模型厂商；
- 外部Agent通过MCP或兼容Bundle读取和维护资产；
- local-first、可导出、可恢复、可删除；
- UI和Agent共享相同业务规则；
- 当前先做最小模型，不做高级披露、多Agent调度和自动策略学习。

## 必须满足

| ID | 约束 |
|---|---|
| AR-001 | Android断网时可读取和维护全部核心资产 |
| AR-002 | Android Vault是唯一权威事实源 |
| AR-003 | Core不依赖Flutter、Android、MCP SDK或模型厂商 |
| AR-004 | UI、MCP和Bundle写入均经过相同Application Commands |
| AR-005 | 事件、投影和必要审计处于原子事务或等价恢复边界 |
| AR-006 | 修订不能静默覆盖历史Execution、Outcome和Strategy版本 |
| AR-007 | AgentInference不能变成UserFact或DeterministicOutcome |
| AR-008 | MCP只暴露领域资源和工具，不暴露数据库、路径和密钥 |
| AR-009 | 只读与读写Session可区分且可失效 |
| AR-010 | D4在持久化、MCP、Bundle和日志多层拒绝 |
| AR-011 | 核心数据可通过版本化JSON/JSONL无损导出 |
| AR-012 | Agent切换不需要迁移业务数据 |
| AR-013 | 模型或网络不可用不破坏本地记录和监督功能 |
| AR-014 | MVP不依赖Android后台常驻保证正确性 |
| AR-015 | 给定同一事件序列可确定性重建相同状态 |

## 质量目标

- 单用户优先；
- 日常记录操作低负担；
- 本地写入快速、原子且可恢复；
- MCP错误稳定、结构化、脱敏；
- Schema显式版本化；
- 附件与结构化数据分离；
- 派生索引可以删除和重建；
- dogfooding证据绑定exact commit。

## 当前待决定

- Android临时MCP的具体SDK和网络栈；
- 局域网配对、TLS与Session token格式；
- Strategy和Outcome的最终字段；
- Context/Proposal Bundle Schema；
- 首个dogfood领域；
- 现有OpenAI/Windows/Sync代码是删除、归档还是保留未接线。

## 延期约束

以下不再阻塞MVP：

- Windows构建；
- Android↔Windows同步；
- Relay部署；
- 多设备撤销；
- 多Agent编排；
- 云端模型路由；
- 渐进披露；
- 训练个人模型。
