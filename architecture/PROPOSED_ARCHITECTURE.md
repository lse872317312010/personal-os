# 推荐逻辑架构 v0.2

状态：proposed for direction review

## 1. 总体原则

采用Android-Authoritative Agent Gateway架构：

- Android Vault保存完整权威事件、资产、投影和附件；
- 外部Agent/Harness负责全部推理；
- MCP Gateway向Agent提供稳定查询与命令；
- Android UI和MCP共享同一Application API；
- Agent写回只能产生经过验证的领域命令和事件；
- JSON/JSONL Bundle提供离线兼容与供应商退出能力。

## 2. 逻辑组件

1. **Android UI Shell**：资产、目标、策略、计划、任务、执行、结果、复盘和Agent连接界面；
2. **Application Core**：命令校验、状态机、事件生成、投影和事务边界；
3. **Policy Engine**：信息类型、D0–D4、Actor、Session、Capability和风险控制；
4. **Local Event Store**：append-only事件、版本、幂等、因果和Schema；
5. **Projection Store**：当前资产、活动目标、策略时间线、今日任务和复盘视图；
6. **Encrypted Blob Vault**：照片、文件和其他大对象；
7. **Agent Gateway Port**：与传输无关的资源查询和工具命令接口；
8. **MCP Adapter**：把Agent Gateway映射为MCP Resources和Tools；
9. **Bundle Adapter**：生成Context Bundle并导入Proposal Bundle；
10. **Agent Audit Store**：Session、调用、写入来源和结果；
11. **Export/Recovery**：无损JSON/JSONL、附件清单、备份和恢复。

## 3. 依赖方向

外层依赖内层：

Android UI / MCP / Bundle
→ Application Commands and Queries
→ Domain / Events / Policy
→ Storage Ports
→ Android Adapters。

Domain、Events、Policy和Application不得依赖Flutter、Android、MCP SDK、HTTP或模型厂商。

## 4. 统一写入路径

Android UI或Agent发起Command
→ Session/Actor检查
→ Schema和领域不变量检查
→ event + projection原子事务
→ 审计记录
→ 返回稳定结果。

MCP和Bundle不得直接访问SQLCipher表或Blob路径。

## 5. 统一读取路径

Agent查询Goal
→ Application Query建立目标相关Context
→ Projection Store读取结构化资产和历史
→ Blob只返回不透明引用和元数据
→ MCP Resource或Context Bundle返回。

MVP暂不做复杂的字段级渐进披露；只区分只读/读写Session以及是否允许访问D2/D3。D4始终拒绝。

## 6. 最小MCP资源

- personal-os://profile
- personal-os://goals/active
- personal-os://goals/{goal_id}/context
- personal-os://assets/{asset_id}
- personal-os://strategies/{strategy_id}
- personal-os://goals/{goal_id}/strategy-history
- personal-os://plans/{plan_id}
- personal-os://reviews/{review_id}

## 7. 最小MCP工具

- search_assets
- get_personal_context
- upsert_asset
- record_observation
- propose_strategy
- create_plan
- record_review
- archive_asset
- get_session_status

Execution和Outcome主要由Android UI采集；后续可开放受控工具给设备连接器。

## 8. Agent写入规则

- 资产写入必须给出来源和information_type；
- 新Strategy必须处于Proposed；
- Strategy必须引用Goal和评价指标；
- Plan必须引用Strategy并有限期；
- Review必须引用Execution/Outcome或明确说明证据不足；
- Agent不能修改历史Execution和Outcome；
- Agent不能把自己的Inference升级为UserFact；
- 任何策略只有在真实证据存在时才能标记为已验证。

## 9. Android MCP传输

MVP候选为前台临时Streamable HTTP服务：

- Vault解锁后由用户启动；
- 局域网或设备隧道内可达；
- 配对产生短期Session；
- App锁定、退出或超时后终止；
- 不依赖后台常驻保证正确性。

如果Agent无法访问Android网络，使用与MCP相同Schema的Context/Proposal Bundle。

具体网络暴露、TLS和认证方案在实现前单独威胁建模。

## 10. 数据存储

继续使用：

- SQLCipher保存事件和结构化投影；
- Android Keystore保护Vault密钥；
- Encrypted Blob Vault保存附件；
- append-only事件保留修订历史；
- Snapshot用于启动性能但不是独立权威。

Graphiti、向量索引或Agent memory只能作为未来可重建派生索引。

## 11. 已延期组件

- App内Model Gateway和特定Provider Client；
- Sync Outbox/Inbox；
- Encrypted Relay；
- Secondary Trusted Device；
- Restricted Collector；
- Windows secure adapter；
- 多Agent Orchestrator；
- 自动策略选择和策略训练。

现有相关代码和文档保留为历史资产，代码处置要在影响分析后决定，不再作为当前MVP主线。
