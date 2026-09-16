# 修订后架构启动输入

状态：direction reset on 2026-09-15

## 已经决定

1. MVP只保留Android；
2. Android Vault保存权威个人资产和策略历史；
3. App不直接接入或绑定特定模型；
4. 外部Agent/Harness负责全部推理；
5. Agent通过MCP或Bundle读写；
6. UI与Agent共享Application Commands/Queries；
7. 第一阶段只做最小模型和两轮Strategy闭环；
8. Windows、同步、多Agent和高级披露延期。

## 当前要回答的问题

1. PersonalAsset、Strategy、Execution、Outcome、Review的最小字段；
2. Strategy版本和验证状态机；
3. AgentRef、AgentSession、只读/读写权限和审计；
4. MCP Resources和Tools的稳定Schema；
5. Context Bundle与Proposal Bundle格式；
6. Android前台临时MCP的网络、认证和生命周期；
7. 现有Appearance/Model代码的迁移方式；
8. 旧事件和新Schema兼容；
9. Redmi两轮dogfood领域、周期和指标。

## 决策顺序

1. 用户审核产品和MVP文档；
2. 冻结最小领域模型；
3. 冻结Context/Proposal Schema；
4. 冻结MCP Resources/Tools；
5. 完成现有代码影响分析；
6. 先实现Bundle vertical slice；
7. 实现Android临时MCP；
8. 完成两个Agent兼容测试；
9. 完成两轮真实dogfood。

## 每项方案必须说明

- 对MVP闭环的直接贡献；
- 对现有事件和数据库的迁移影响；
- 数据和信任边界；
- Android运行限制；
- Agent兼容与供应商退出；
- 失败和恢复行为；
- 测试与真机证据；
- 可以延期的复杂度。

## 当前禁止提前决定

在最小Schema冻结前，不引入：

- Graphiti或向量数据库；
- 多Agent orchestrator；
- 自动模型选择；
- 云端Relay；
- Windows客户端；
- 高级渐进披露；
- 个人神经网络训练。
