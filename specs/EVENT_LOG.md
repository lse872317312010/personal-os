# M1 事件日志契约 v0.1

状态：draft / append-only logical contract

## 目标

事件日志回答：发生了什么、何时生效、何时记录、由谁触发、基于什么、改变哪个对象，以及是否授权。它不是调试日志，也不能保存秘密。

## 事件信封

`event_id`、`event_type`、`event_version`、`occurred_at`、`recorded_at`、`actor`、`subject_refs`、`correlation_id`、`causation_id`、`source_refs`、`consent_refs`、`sensitivity`、`payload`、`integrity`。

## 首批事件类型

- 信息：`source.registered`、`observation.recorded`、`claim.proposed|confirmed|disputed|expired|withdrawn`
- 目标：`goal.created|activated|paused|completed`、`constraint.recorded`、`preference.recorded|revised`
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

## 禁止内容

密码、验证码、API key、私钥、恢复码；无必要的原始人像或聊天全文；未经授权的第三方敏感画像；可能泄露 D2/D3 的自由文本调试副本。

