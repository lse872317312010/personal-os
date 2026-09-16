# 逻辑包与依赖边界 v0.2

状态：proposed for implementation review

## 目标布局

apps/personal_os_app  
packages/domain  
packages/events  
packages/policy  
packages/application  
packages/storage_api  
packages/agent_gateway_api  
packages/exchange_schema  
adapters/sqlite_vault  
adapters/blob_vault  
adapters/device_security  
adapters/mcp_gateway  
adapters/bundle_exchange

现有sync_api、model_gateway_api、sync_relay和model provider adapters暂时保留但退出MVP组合根，待代码影响分析决定归档或删除。

## 职责

| 包 | 职责 | 禁止 |
|---|---|---|
| domain | PersonalAsset、Goal、Strategy、Plan、Execution、Outcome、Review | UI、网络、数据库 |
| events | 事件信封、事件目录、reducer | 平台与MCP依赖 |
| policy | 信息类型、D0–D4、AgentSession、Capability和风险 | 绕过失败关闭 |
| application | Commands、Queries、事务和用例 | 直接访问Flutter或HTTP |
| storage_api | Event、Projection、Blob、Audit ports | SQLCipher具体类型 |
| agent_gateway_api | Agent可见资源、命令和稳定错误 | MCP SDK与厂商类型 |
| exchange_schema | Context/Proposal/Export版本化Schema | 业务存储实现 |
| sqlite_vault | SQLCipher事件和投影实现 | 定义领域语义 |
| blob_vault | 加密附件实现 | 暴露原始路径 |
| device_security | Keystore与Vault Session | 保存业务数据 |
| mcp_gateway | MCP传输与Schema映射 | 直接写数据库 |
| bundle_exchange | 离线导入导出 | 绕过Application验证 |
| personal_os_app | Android UI和组合根 | 自行推理或绑定模型 |

## 依赖方向

app/adapters
→ agent_gateway_api / exchange_schema / storage_api / application
→ events / policy / domain。

## 核心接口

- CommandBus.execute(command, actorContext)
- QueryService.read(query, authorizationContext)
- EventStore.append(expectedVersion, events)
- ProjectionStore.apply(events)
- BlobStore.put/read/delete(blobRef)
- AgentGateway.open/closeSession
- AgentGateway.readResource
- AgentGateway.executeTool
- ContextExporter.export
- ProposalImporter.validateAndApply

MCP Adapter只转换协议，不拥有业务用例。

## MVP组合根

Android production composition包含：

- secure Vault；
- SQLCipher EventStore；
- encrypted BlobStore；
- Android UI；
- Agent Gateway；
- MCP或Bundle Adapter。

它不包含：

- OpenAI Responses Client；
- 模型credential provider；
- Windows adapter；
- Relay/Sync worker；
- 多Agent orchestrator。
