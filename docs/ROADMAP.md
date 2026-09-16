# 发展路线与里程碑

## 当前产品方向

Personal OS是Android-first、Agent-agnostic的个人策略资产与反馈闭环系统。外部Agent负责推理，Android负责权威数据、执行监督和结果历史。

## M0：产品与领域契约 — Completed

已完成：

- 个人状态、目标、约束、计划、任务和反馈概念；
- 事实、推断、建议和未知项分离；
- D0–D4数据分类；
- 风险和人工确认边界。

2026-09-15产品使命发生方向修正：不再以App内模型分析为MVP主线，改为外部Agent通过MCP维护资产、策略和复盘。

## M1：Core Data Model & Event Log — Completed，需要增量扩展

现有事件、状态机、Consent、删除、冲突和Schema演进继续保留。

新增工作：

- [ ] PersonalAsset明确化；
- [ ] Strategy一等实体与版本状态机；
- [ ] Execution、Outcome、Review证据关系；
- [ ] AgentSession、AgentRef和调用审计；
- [ ] Context/Proposal Envelope；
- [ ] 新增契约fixtures并验证旧事件兼容。

## M2：Android权威Vault基线 — In Progress

保留并完成：

- [x] Flutter Android Shell；
- [x] Dart-first core和ports/adapters边界；
- [x] Android Keystore primitive；
- [x] SQLCipher/EventStore实现；
- [x] Encrypted Blob与受控照片输入；
- [x] Task/Review基础UI；
- [ ] 按新领域模型完成Schema和projection迁移；
- [ ] Redmi冷启动、杀进程、锁屏和恢复验证；
- [ ] Android无损JSON/JSONL导出与恢复；
- [ ] 移除生产流程对内置模型的依赖。

Windows、多设备同步、Relay和云端模型路由从M2退出条件中移除并延期。

## M3：MCP Agent Gateway

目标：外部Agent可以安全、稳定地维护Personal OS。

- [ ] 定义厂商无关MCP Resources和Tools；
- [ ] 读取活动Goal和相关Context；
- [ ] 查询资产与策略历史；
- [ ] 维护PersonalAsset和Observation；
- [ ] 创建Strategy、Plan和Review；
- [ ] 只读/读写Session；
- [ ] 稳定错误码与审计；
- [ ] Android前台临时Streamable HTTP MCP；
- [ ] Context Bundle与Proposal Bundle；
- [ ] 使用Codex完成首个真实连接；
- [ ] 使用第二种Agent/Harness验证可替换性。

退出条件：两个不同Agent使用同一协议读取并延续同一Goal历史。

## M4：两轮策略Dogfooding

目标：验证真实策略闭环，而不是只验证接口。

第一轮：

- 建立一个真实Goal；
- Agent创建Strategy v1与Plan；
- App监督有限周期执行；
- 保存Execution、Outcome和Feedback。

第二轮：

- Agent读取第一轮历史；
- 创建Review与Strategy v2；
- 执行第二轮；
- 对比结果并记录策略变化。

退出条件见ACCEPTANCE_CRITERIA。

## M5：策略资产增强

MVP成功后再加入：

- 策略效果统计；
- 相似条件检索；
- 跨领域策略迁移；
- Graphiti或其他可重建时态索引；
- 多Agent候选比较；
- 自动模型/Harness选择；
- 更精细的Agent授权与披露；
- 数据连接器和传感器输入。

## M6：多设备与平台化

后续候选：

- Windows Secondary Trusted Device；
- Android↔Windows E2EE；
- Encrypted Relay；
- Restricted Collector；
- iOS/Web；
- 多用户和商业化。

## 当前明确暂停

- Android内置OpenAI Responses调用；
- 特定模型ID和API Key输入体验；
- Windows portability后续开发；
- Windows secure adapter；
- 多设备同步；
- 多Agent编排；
- 自动策略选择；
- 高级渐进披露；
- 个人模型训练。

## 最近三个执行节点

1. 完成文档方向重构并由用户审核；
2. 对现有代码做保留/改造/移除影响分析；
3. 冻结MCP Schema和Strategy生命周期后再恢复开发。
