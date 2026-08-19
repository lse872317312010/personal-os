# M1 状态机 v0.1

状态：draft for review

## 通用规则

- 状态只由已接受事件转换；
- 每个转换声明前置状态、Actor 权限和必要 Consent；
- 非法转换不改变投影，并产生结构化拒绝结果；
- terminal 状态默认不能恢复，恢复必须创建新逻辑对象或显式 replacement；
- 迟到事件按其现实时间重新计算有效投影，但不能改变审计顺序。

## Claim

| From | Event | To | 规则 |
|---|---|---|---|
| none | claim.proposed | proposed | 必须有 statement 和 evidence/unknown 标记 |
| proposed | claim.confirmed | confirmed | 用户确认或可信规则，保留原证据 |
| proposed/confirmed | claim.disputed | disputed | 用户可直接质疑；自动 Actor 只能提出质疑 |
| proposed/confirmed/disputed | claim.expired | expired | 到期或复核失败 |
| proposed/confirmed/disputed | claim.withdrawn | withdrawn | 来源撤回、纠错或删除影响 |

`expired`、`withdrawn` 为 terminal；新证据创建新 revision，不复活旧 revision。

## Goal

`none → draft → active ↔ paused → achieved | abandoned | replaced`

- active 前必须有 success_criteria 与 time_horizon；
- replaced 必须引用 successor Goal；
- achieved 只能由用户确认或满足已确认的确定性规则触发。

## Plan

`none → draft → approved → active ↔ paused → completed | stopped`

- approved 需要有效用户 Consent；
- active 需要 start/end 或明确有限周期；
- completed 需要 Review 入口事件；
- 风险或约束突破触发 paused/stopped，不能静默调整。

## Task

`none → planned → ready → in_progress → completed | failed | skipped | stopped`

- completed 必须引用 ExecutionRecord；
- skipped 表示用户选择不执行，不等于 failed；
- failed 表示尝试但未满足完成条件；
- stopped 表示风险、计划停止或依赖失效。

## Consent

`none → requested → granted → revoked | expired`

- granted 必须包含 purpose、scope、subject/data、actions、validity；
- scope 扩大创建新 Consent，不修改原 Consent；
- revoked 立即阻止新的依赖操作；
- 已完成操作的历史审计不因撤销而消失。

## Review

`none → draft → user_reviewed → accepted | rejected`

- accepted 后才能将 model.revision.proposed 转为 accepted；
- rejected 保留历史但不得修改当前模型；
- 自动 Actor 可创建 draft，不能代替用户进入 accepted。

