# M1 事件日志契约 v0.1

状态：accepted / append-only logical contract

## 目标

事件日志回答：发生了什么、何时生效、何时记录、由谁触发、基于什么、改变哪个对象，以及是否授权。它不是调试日志，也不能保存秘密。

## 事件信封

`event_id`、`event_type`、`event_version`、`occurred_at`、`recorded_at`、`actor`、`subject_refs`、`correlation_id`、`causation_id`、`source_refs`、`consent_refs`、`sensitivity`、`payload`、`integrity`。

## 首批事件类型

- 信息：`source.registered`、`observation.recorded`、`claim.proposed|confirmed|disputed|expired|withdrawn`
- 目标：`goal.created|revised|activated|paused|completed`、`constraint.recorded`、`preference.recorded|revised`
- 个人事实：`personal_asset.recorded|revised|superseded|archived`
- 计划：`baseline.created`、`opportunity.identified`、`recommendation.created`、`plan.drafted|approved|activated|paused|completed|stopped`
- 任务：`task.planned|completed|skipped|failed|stopped`、`execution.recorded`
- 反馈：`outcome.recorded`、`review.created|accepted|rejected`、`model.revision.proposed|accepted`
- 治理：`consent.requested|granted|revoked|expired`、`export.requested|completed`、`deletion.requested|completed|partially_completed`

## 写入规则

- append-only，业务事件不能原地修改；
- 重复 event_id 不产生第二次状态变化；
- 优先引用对象，不复制 D2/D3 原始内容；
- 自动事件记录 causation_id；
- 依赖授权的事件记录 consent_refs；
- occurred_at 解释现实顺序，recorded_at 保留审计顺序；
- 失败、拒绝和跳过必须显式记录。

## 投影规则

1. 按 recorded_at 和稳定 tie-breaker 读取；
2. 验证 schema、actor、引用、Consent 和敏感度；
3. 根据 occurred_at 应用领域时间语义；
4. 非法状态跳转显式失败，不静默修正；
5. 撤销、过期和 supersede 更新当前可用集合；
6. 冲突保留到显式 Decision 或 Review；
7. Snapshot 只是加速结果，必须可由事件验证。

## 纠错与删除

纠错使用新事件，不重写历史。删除区分业务不可见、原始内容擦除、最小 tombstone、审计事件和备份传播。具体物理策略留给 M2，但必须满足 `AC-407`。

Web 目标资料的编辑由用户触发，并引用原对象固定版本、校验所属 profile 与 `expected_revision`。目标文本或成功标准变化时追加 `goal.revised`；当前情况变化或清空时分别追加 `personal_asset.revised` 或 `personal_asset.archived`；执行约束变化或清空时分别追加 `constraint.revised` 或 `constraint.archived`。对象 ID 保持不变，修订增加 revision，归档保留最后内容供审计但不再作为当前约束。多个字段一次保存时在同一批次追加，避免出现只更新一半的个人资料。此前版本继续作为历史证据读取，已经接受的策略不变。新事件为 v1 信封的新增类型，旧客户端无法解释时必须拒绝或隔离，不能当作已经处理。

## 禁止内容

密码、验证码、API key、私钥、恢复码；无必要的原始人像或聊天全文；未经授权的第三方敏感画像；可能泄露 D2/D3 的自由文本调试副本。

## 配套规范

- [状态机](STATE_MACHINES.md)
- [授权模型](AUTHORIZATION.md)
- [端到端事件序列](EVENT_SEQUENCES.md)
- [删除、快照与压缩](RETENTION_AND_SNAPSHOTS.md)
- [契约测试](CONTRACT_TESTS.md)
- [并发与冲突](CONCURRENCY_AND_CONFLICTS.md)
- [Schema 演进](SCHEMA_EVOLUTION.md)
- [敏感度继承](SENSITIVITY_PROPAGATION.md)
