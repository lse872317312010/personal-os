# M1 核心数据模型 v0.1

状态：draft / technology-neutral

## 通用元数据

所有持久核心对象包含：`id`、`schema_version`、`created_at`、`effective_at`、`recorded_at`、`actor`、`source_refs`、`sensitivity`、`status`、`revision`、`supersedes`。

`effective_at` 与 `recorded_at` 必须分开，以支持迟到记录和历史修订。

## 核心对象

- Source：用户、设备、文件、外部资料或模型等信息来源；
- Observation：带 subject、domain、attribute、value、unit、method、quality 的观察；
- Claim：带证据、置信度、有效期和状态的可争议判断；
- Goal：desired outcome、成功标准、优先级、时间范围和约束；
- Constraint / Preference：硬限制与主观权重必须分离；
- Baseline：某领域在某时间点的版本化状态引用集合；
- Opportunity / Recommendation：目标差距及其候选行动；
- Plan / Task：有限周期计划和最小可验证动作；
- ExecutionRecord / Outcome / Review：真实执行、结果与结构化复盘；
- Consent / Decision：数据/动作授权与显式选择理由。

## 状态机

- Claim：`proposed → confirmed | disputed → expired | withdrawn`
- Goal：`draft → active → paused → achieved | abandoned | replaced`
- Plan：`draft → approved → active → paused → completed | stopped`
- Task：`planned → ready → in_progress → completed | skipped | failed | stopped`
- Consent：`requested → granted → expired | revoked`
- Review：`draft → user_reviewed → accepted | rejected`

任何状态跳转必须由事件触发，禁止静默改写。

## 引用与版本规则

- 对象 ID 表示逻辑身份，revision 表示版本；
- 修订创建新版本，不覆盖旧版本；
- 引用默认固定到具体 revision；
- 当前状态由有效事件投影得到；
- 冲突 Claim 可以共存，但必须显示冲突；
- withdrawn、expired 或 superseded 对象不参与当前推荐。

## 不变量

- Recommendation 追溯到 Goal、Opportunity 和 Evidence；
- active Plan 有有效 Consent 和有限周期；
- completed Task 有 ExecutionRecord；
- Review 不能覆盖 Observation；
- D4 不出现在持久字段或事件载荷；
- 撤销 Consent 后不创建新的依赖处理结果；
- 用户纠错优先于后续自动推断，除非有新证据并明确复核。

## 待细化

详细规则拆分为：

- [状态机](STATE_MACHINES.md)
- [Actor、权限与 Consent](AUTHORIZATION.md)
- [删除、保留、快照与压缩](RETENTION_AND_SNAPSHOTS.md)
- [契约测试](CONTRACT_TESTS.md)

仍待最终审查：并发冲突的显式解决事件、Schema 演进兼容表和字段级敏感度继承。
