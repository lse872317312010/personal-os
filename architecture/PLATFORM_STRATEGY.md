# 平台策略 v0.2

状态：accepted for revised MVP

## 已冻结结论

- MVP用户端只保留Android；
- Redmi Turbo是首个dogfooding和Primary Vault设备；
- Flutter继续作为Android UI框架；
- domain/application core保持纯Dart和平台无关；
- Android App不内置特定大模型或Agent Harness；
- Codex和其他Agent在外部运行，通过MCP或Bundle访问；
- Windows、iOS、Web、多设备同步和Relay全部延期；
- Rust和Tauri不进入MVP。

## Android职责

Android负责：

1. Vault解锁与密钥生命周期；
2. PersonalAsset、Goal、Constraint和Observation维护；
3. Strategy、Plan、Task、Execution、Outcome和Review展示；
4. 今日任务与执行监督；
5. 用户反馈和确定性结果采集；
6. Agent写入审核和历史追踪；
7. MCP Session建立与关闭；
8. Context/Proposal Bundle导入导出；
9. 备份、恢复和删除。

Android不负责：

- 模型推理；
- Prompt管理；
- Agent规划循环；
- 模型路由；
- 厂商API key输入；
- 多Agent协调。

## 外部Agent职责

外部Agent负责：

- 分析目标上下文；
- 维护或提出PersonalAsset修订；
- 提出Strategy；
- 生成Plan和Tasks；
- 根据Execution、Outcome和Feedback生成Review；
- 创建Strategy新版本；
- 必要时向用户提出补充数据请求。

Agent不得成为数据权威，不能绕过Application Core。

## 手机交互主线

1. 解锁Vault；
2. 查看或维护个人资产；
3. 创建Goal和Constraint；
4. 建立Agent Session；
5. 审核Agent产生的资产修订、Strategy和Plan；
6. 执行今日Task；
7. 快速记录完成、跳过、偏离和反馈；
8. 查看Outcome和Review；
9. 对比Strategy版本；
10. 导出或恢复。

## MCP连接候选

第一实现优先考虑Android前台临时HTTP服务：

- 用户主动开启；
- 短期配对；
- 只读/读写权限；
- 锁屏或关闭后失效；
- 不依赖后台常驻；
- 首先服务同一局域网或受控隧道中的Codex CLI/Harness。

网络可达性不能阻塞核心闭环，因此Context/Proposal Bundle是MVP必备后备接口。

## 跨平台边界

虽然MVP只发布Android，但以下包继续保持平台无关：

- domain；
- events；
- policy；
- application；
- Agent Gateway协议；
- Context/Proposal Schema；
- Export Schema。

“平台无关”不再意味着当前必须开发Windows客户端。

## MVP发布顺序

| 顺序 | 目标 | 退出证据 |
|---:|---|---|
| 1 | Android权威资产与策略历史 | Redmi离线、冷启动、恢复通过 |
| 2 | Context/Proposal Bundle | 一个Agent完成读写往返 |
| 3 | Android MCP Gateway | Codex完成真实Session |
| 4 | 第二Agent兼容验证 | 不修改核心Schema即可延续历史 |
| 5 | 两轮真实dogfood | Strategy v2引用v1结果 |

## 延后路线

只有两轮dogfood证明产品价值后，才重新评估：

- Windows Secondary Trusted Device；
- 多设备E2EE；
- Encrypted Relay；
- Restricted Collector；
- iOS/Web；
- 后台长期Agent连接。
