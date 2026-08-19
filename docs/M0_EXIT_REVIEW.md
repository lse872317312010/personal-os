# M0 退出评审

- 评审日期：2026-08-20
- 结论：通过，带一项非阻塞证据债务
- 下一阶段：M1 Core Data Model & Event Log

## 冻结项

| 冻结项 | 依据 | 结果 |
|---|---|---|
| 产品章程 | `PROJECT_CHARTER.md` | accepted |
| 原则与非目标 | `PRODUCT_PRINCIPLES.md` | accepted |
| 首批领域 | 健身、饮食、外形、关系 | accepted |
| 首个 MVP 方向 | 最小分析能力 + 完整行动反馈闭环 | accepted |
| MVP 范围 | `MVP_SCOPE.md` | accepted |
| 核心实体与状态 | `DOMAIN_MODEL.md` | accepted for M1 input |
| 验收标准 | `ACCEPTANCE_CRITERIA.md` | accepted for design validation |
| 数据与风险边界 | `DATA_POLICY.md`、`RISK_CONTROL_MATRIX.md` | accepted |

## 退出判断

- 核心问题、用户价值和非目标已经明确；
- MVP 是端到端纵向切片，不是功能集合；
- 产品语义不依赖具体语言、框架、数据库或模型；
- 事实、观察、推断、建议和未知项必须分离；
- 数据控制、人工确认和禁止边界足以约束 M1；
- M1 可以在不实现完整产品的情况下建立可测试契约。

## 已知证据债务

2026-08-17“男士外貌分析”原始对话尚未形成逐条脱敏证据摘要。现有外形需求主要是 E2 项目上下文和 E1 工作假设。

- 不把缺失原文支持的细节提升为 E3；
- M1 只设计跨领域核心语义，不固化具体外形判断算法；
- 在 M3 dogfooding 前完成 Issue #2；
- 若原始证据推翻 MVP 方向，通过新决策记录修订，不篡改历史。

## 阶段授权

用户明确要求“继续然后进入 M1”，因此接受 M0 阶段转换和当前推荐的最小组合 MVP 主线。这不代表批准具体技术架构，也不代表所有候选需求均被冻结。

