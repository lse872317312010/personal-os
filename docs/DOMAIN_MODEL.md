# 领域概念模型

状态：M0 概念模型。用于统一语言和验证需求，不规定数据库、类、服务或 API。

## 1. 核心概念

| 概念 | 含义 | 关键属性 |
|---|---|---|
| Person | Personal OS 服务的主体 | 身份边界、授权主体 |
| Domain | 健身、饮食、外形、关系等决策领域 | 名称、范围、风险级别 |
| Goal | 希望达到或维持的结果 | 时间范围、优先级、状态、成功标准 |
| Constraint | 限制可选行动的条件 | 类型、强度、有效期、可协商性 |
| Preference | 主观选择倾向，不等于客观事实 | 适用范围、权重、来源、更新时间 |
| Source | 信息来自哪里 | 用户、设备、文件、外部资料、模型 |
| Observation | 对某一时点状态的记录 | 时间、来源、质量、敏感度 |
| Claim | 关于个人或环境的可判断陈述 | 类型、证据、置信度、有效期、状态 |
| Baseline | 某领域在某一时间的版本化状态快照 | 观察集合、确认状态、版本 |
| Opportunity | 从基线与目标差距产生的候选改善点 | 影响、成本、周期、风险、可逆性 |
| Recommendation | 针对机会提出的行动建议 | 依据、未知项、替代方案、确认要求 |
| Plan | 为实现目标组织的一组有限周期行动 | 开始/结束、预算、复盘点、状态 |
| Task | 可执行和可验证的最小行动单元 | 完成条件、频率、依赖、停止条件 |
| ExecutionRecord | 任务实际发生了什么 | 完成、跳过、困难、成本、不良反应 |
| Outcome | 周期内观察到的结果 | 指标、变化、主观评价、混杂因素 |
| Review | 对目标、计划与结果的结构化复盘 | 结论、置信度、修订、下一步 |
| Decision | 用户或系统在约束下作出的选择 | 选项、理由、授权、影响范围 |
| Consent | 对数据使用或外部动作的明确授权 | 对象、用途、范围、有效期、撤销状态 |

## 2. 信息类型必须分离

`Observation`、`Claim` 和 `Recommendation` 不能混为一体：

- Observation：记录“看到了什么”；
- Claim：表达“这些信息可能意味着什么”；
- Recommendation：表达“基于目标建议做什么”。

同一结论允许存在多个版本或相互冲突的 Claim。用户确认不会把推断变成绝对真理，只会改变其状态和使用权重。

## 3. 最小关系

- Person 拥有 Goals、Constraints、Preferences 与 Consents；
- Domain 组织 Observations、Baselines、Opportunities 和 Plans；
- Source 支持 Observation 或 Claim；
- Baseline 聚合某一时点有效的 Observations 与 Claims；
- Goal 与 Baseline 的差距产生 Opportunities；
- Recommendation 针对 Opportunity，并受 Constraints 与 Consent 限制；
- Plan 选择 Recommendations 并分解为 Tasks；
- ExecutionRecord 记录 Task 的实际执行；
- Outcome 汇总新的观察；
- Review 比较 Goal、Baseline、Plan 与 Outcome，并产生 Decisions；
- Decision 可以修订 Goal、Constraint、Preference、Claim 或下一轮 Plan。

## 4. 生命周期

### Claim

`proposed → confirmed / disputed → expired / withdrawn`

### Goal

`draft → active → paused → achieved / abandoned / replaced`

### Plan

`draft → approved → active → paused → completed / stopped`

### Consent

`requested → granted → expired / revoked`

撤销 Consent 后，后续使用必须停止；历史记录是否保留取决于数据政策和审计必要性，不能由技术实现默认决定。

## 5. 领域不变量

1. 没有 Source 的高影响 Claim 不得被当作已确认事实；
2. Recommendation 必须能追溯到 Goal、Opportunity 和依据；
3. 高风险 Recommendation 未经授权不得进入 active Plan；
4. ExecutionRecord 只能记录真实发生的行为；
5. Review 不得覆盖历史，只能创建修订版本；
6. 过期或撤销的 Claim 不得继续参与当前决策，除非明确说明用途；
7. D4 信息不得成为任何领域对象的持久内容；
8. 跨领域读取必须同时满足必要性、权限和敏感度规则。

## 6. 尚未进入本模型的内容

- Agent、工作流引擎、向量库、事件总线等技术概念；
- 具体 UI 页面和交互组件；
- 数据库表、API 或序列化格式；
- 模型供应商和提示词结构。

这些内容只能在 M2 根据冻结需求映射。

