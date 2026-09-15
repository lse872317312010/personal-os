# 架构方案结论 v0.2

状态：direction frozen；implementation pending

## 1. 已接受组合

| 维度 | 决定 |
|---|---|
| 用户平台 | Android only MVP |
| 首个设备 | Redmi Turbo |
| UI | Flutter |
| Core | 纯Dart domain/application/events/policy |
| 权威数据 | Android local Vault |
| 结构化存储 | SQLite/SQLCipher事件与投影 |
| 密钥 | Android Keystore |
| 附件 | 独立Encrypted Blob Vault |
| 推理 | 外部Agent/Harness |
| 在线接口 | MCP |
| 离线接口 | Context/Proposal Bundle |
| 导出 | 版本化JSON/JSONL |
| Agent写入 | 统一Application Commands |
| 模型厂商 | 不绑定 |

## 2. Agent接口方案

### 直接厂商API嵌入App

优点：调用路径短。  
问题：绑定Provider、credential和媒体协议；App承担推理与模型生命周期。  
结论：退出MVP主线。

### 自定义REST接口

优点：简单、通用、容易测试。  
问题：每个Harness需要自定义集成，缺少Agent资源/工具发现语义。  
结论：可作为内部或兼容接口，不作为首选标准。

### MCP Agent Gateway

优点：Codex及其他Agent/Harness可发现资源和工具；数据与推理解耦；利于替换Agent。  
问题：Android网络可达、Session、TLS和生命周期需要验证。  
结论：Recommended online interface。

### Context/Proposal Bundle

优点：无需后台服务；适用于云端Agent和不可直连环境；最容易验证Schema。  
问题：不是实时交互，需要导出导入。  
结论：Required MVP compatibility path，且应先于实时MCP实现。

## 3. MCP宿主候选

| 方案 | 优点 | 问题 | 当前判断 |
|---|---|---|---|
| Android前台临时HTTP | 数据不离开权威端；生命周期清晰 | 局域网和客户端可达性 | 首选Spike |
| PC Companion | stdio兼容好 | 引入第二平台和副本 | MVP延期 |
| 云端Remote MCP | 云Agent易访问 | 权威同步、认证和隐私复杂 | 延期 |
| 文件Bundle | 无网络暴露 | 非实时 | MVP必备 |

## 4. 当前不重新比较

以下结论继续成立：

- SQLCipher + Keystore适合Android Vault；
- append-only事件适合策略版本和审计；
- Blob与结构化数据分离；
- CRDT不作为核心事件存储；
- Flutter UI不能直接读写数据库；
- Rust只有测量证明必要时才引入。

## 5. 已延期候选

- Windows/Tauri/Rust desktop；
- E2EE Relay；
- Restricted Collector；
- Graphiti、Mem0和向量索引；
- 多Agent orchestrator；
- 自动模型选择；
- 高级披露控制；
- 个人模型训练。

## 6. 下一次技术决策

在继续编码前依次冻结：

1. 最小领域Schema；
2. Context/Proposal Envelope；
3. MCP Resource/Tool Schema；
4. Android Session与传输；
5. 旧代码迁移方案。
