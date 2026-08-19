# M2 推荐逻辑架构 v0.1

状态：architecture principle accepted；technology mapping proposed

## 核心原则

采用 **Local-Authoritative Encrypted Hybrid**：可信主设备保存完整 Vault 和可用投影；服务器只作为加密事件/Blob 中继、设备目录和同步协调者，不能成为业务明文权威。

## 逻辑组件

1. **UI Shell**：目标、基线、计划、执行、复盘、权限和冲突界面；
2. **Application Core**：命令校验、状态机、事件生成、投影和契约测试；
3. **Policy Engine**：D0–D4、R0–R4、Actor/Capability/Consent；
4. **Local Event Store**：append-only 事件、幂等键、因果和 Schema 版本；
5. **Projection Store**：当前状态、查询视图和 Snapshot；
6. **Encrypted Blob Vault**：照片、导入材料和大对象，独立密钥/删除；
7. **Sync Outbox/Inbox**：密文事件包、重试、缺口检测和历史补采；
8. **Restricted Collector**：公司电脑等不可信度较低设备，只做最小采集和加密上传；
9. **Encrypted Relay**：密文存储、设备队列、ack/cursor，不理解业务载荷；
10. **Model Gateway**：按敏感度和 Consent 路由本地或云端模型，输出仍需 Policy/Core 验证。

## 设备角色

| 角色 | 能力 | 禁止 |
|---|---|---|
| Primary Vault Device | 完整本地事件、投影、D3 Vault、密钥与复盘 | 无授权对外共享 |
| Secondary Trusted Device | 选择性同步的领域/时间范围，可离线写事件 | 默认下载全部 D3 |
| Restricted Collector | 采集、OCR、加密封装、上传、缺口报告 | 完整 Vault、长期 D3 投影、模型全局记忆 |
| Relay | 密文排队、ack、设备撤销、缺口索引 | 解密业务内容、生成 Claim、解决冲突 |

## 写入路径

`UI/Collector → Command → Policy Check → Local Transaction(event + projection + outbox) → UI immediate result → encrypted sync`

业务提交不等待云端。Event、Projection 和 Outbox 必须处于一个原子事务或具备等价恢复语义。

## 同步路径

- 每设备拥有稳定 device_id 与签名身份；
- 事件使用全局 event_id、device sequence、causation/correlation；
- 上传前按目标设备/账户密钥加密并签名；
- 中继只确认密文包和 cursor；
- 接收端验证签名、Schema、Consent、敏感度和状态机后才进入事件日志；
- 缺号触发 gap detection 和补采；
- 冲突生成 M1 `conflict.*` 事件，不自动覆盖。

## 模型边界

- D0/D1：可按成本和能力选择本地/云端；
- D2：云端前需用途限定、最小化和可见 Consent；
- D3：默认本地；云端仅单次明确授权、最小输入且不进入供应商长期记忆；
- D4：不进入模型；
- 模型输出只能提出 Observation/Claim/Recommendation 草案，不能直接修改已确认状态或执行 R2+ 动作。

## 为什么暂不以 CRDT 为核心

核心对象包含 Consent、删除、风险和状态机，它们需要显式拒绝与冲突，而不是“总能合并”。因此同步传递事件并由领域投影器裁决；CRDT 只保留给未来可以安全自动合并的低风险文档。

## 已细化规范

- [客户端 Spike 计划](CLIENT_SPIKE_PLAN.md)
- [客户端评分表](CLIENT_SCORECARD.md)
- [同步协议](SYNC_PROTOCOL.md)
- [密钥管理](KEY_MANAGEMENT.md)
- [M1 架构走查](M1_ARCHITECTURE_WALKTHROUGH.md)
