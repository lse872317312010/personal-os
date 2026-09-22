# 发展路线与里程碑

## 当前产品方向

Personal OS 是 Android-first、Agent-agnostic 的个人策略资产与反馈闭环系统。外部 Agent/Harness 负责推理，Android Vault 负责权威数据、用户确认、执行监督和历史连续性。

## M0：产品与领域契约 — Completed

- Android-only MVP、Redmi Primary Vault；
- 外部 Agent 推理与 Android 权威边界；
- 事实、观测、结果、反馈、推断和建议分离；
- D0–D4 数据分类与 R0–R4 风险边界；
- Windows、同步、Relay、内置模型和多 Agent 编排延期。

## M1：Core Data Model & Event Log — Completed

- PersonalAsset、Goal、Strategy、Execution、Outcome、Review、AgentSession；
- append-only 事件、revision、谱系、确定性投影；
- Strategy proposed/accepted/active 生命周期；
- Agent 提案与用户执行/结果权限分离；
- 旧事件兼容和 SQLite schema v2 migration。

## M2：Android 权威 Vault — Build verified，device verification pending

已完成：

- [x] Flutter Android Shell 与 Dart-first core；
- [x] Android Keystore + native SQLCipher；
- [x] Encrypted Blob、Photo Picker 与 Camera；
- [x] EventStore 完整分页与冷启动投影恢复；
- [x] 口令加密 `.posb` 备份、认证导入、原子恢复与强制重锁；
- [x] APK SHA-256、provenance 与 rolling Release；
- [x] G3 九场景的唯一规范、schema v2 与验证器。

剩余：

- [ ] 在同一已验证 APK 上完成 Redmi 九场景；
- [ ] 保存去敏的 real-device v2 证据；
- [ ] 不以 CI、模拟器或 synthetic record 替代真机结论。

## M3：Agent Gateway — Protocol complete，live transport pending

已完成：

- [x] 厂商无关 Agent Protocol v0；
- [x] 固定 revision 的 Context Bundle；
- [x] Proposal Bundle 与 Review Bundle；
- [x] read/write Session、Harness 身份绑定与关闭失效；
- [x] Application Command 权限边界；
- [x] 第二 Harness 接续同一历史的契约测试；
- [x] Android 离线复制/导入兼容路径；
- [x] MCP 2025-06-18 JSON-RPC握手、工具发现、调用适配和稳定错误；
- [x] 每次调用重验Session生命周期、Harness身份和授予的capability。

剩余：

- [x] 冻结 Android 前台临时 MCP 传输威胁模型；
- [ ] 仅在 Vault 解锁且用户显式启动时开放；
- [ ] 短期凭证、loopback/ADB 或受控局域网绑定；
- [ ] 锁定、退后台、超时和 Session 关闭时立即终止；
- [ ] 用真实外部 Harness 完成在线连接，不能放宽离线路径的同一校验。

## M4：两轮真实策略 Dogfooding — Not run

同一 Goal、同一候选版本、2–6 周内完成：

第一轮：

- Strategy v1 与有限期 Plan；
- 用户确认、真实 Execution、Outcome 和 Feedback；
- Agent Review 明确引用第一轮证据。

第二轮：

- 不同 Harness 接续完整历史；
- Strategy v2 以 v1 为 parent；
- v2 明确使用 v1 证据并因反馈产生可解释变化；
- 完成第二轮执行、结果和两轮比较。

退出条件：

- G0–G4 schema v2 审计输出 `DOGFOOD_READY`；
- 用户确认连续策略或复盘价值高于一次性对话；
- 无 Critical/High 未缓解的数据完整性或安全缺陷。

## M5：策略资产增强 — Deferred until M4 passes

- 策略效果统计与相似条件检索；
- 跨领域策略迁移；
- 可重建时态索引；
- 多 Agent 候选比较与细粒度授权；
- 数据连接器和传感器输入。

## M6：多设备与平台化 — Deferred

- Windows Secondary Trusted Device；
- Android↔Windows E2EE；
- Encrypted Relay 与 Restricted Collector；
- iOS/Web、多用户和商业化。

## 当前明确暂停

- Android 内置 OpenAI/其他模型 SDK；
- App 内 API Key 与模型选择；
- Windows 生产开发；
- 多设备同步与 Relay；
- 多 Agent 编排和自动策略选择；
- 高级渐进披露、向量数据库和个人模型训练。

## 最近三个执行节点

1. Redmi 使用 exact commit + exact APK 完成 G3 九场景；
2. 在独立威胁模型通过后实现 Android 前台临时 MCP 传输；
3. 选择一个真实 Goal，按 G4 schema v2 启动两轮 2–6 周 dogfood。
