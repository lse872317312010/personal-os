# M1 Actor、权限与 Consent v0.1

状态：draft for review

## ActorRef

最小字段：

- `actor_id`：稳定标识；
- `actor_type`：`user | agent | connector | importer | system`；
- `authority_source`：直接用户操作、Consent、系统规则或导入声明；
- `session_or_run_id`：可选的执行边界；
- `on_behalf_of`：非用户 Actor 必须指向授权主体；
- `capability_refs`：本次事件实际使用的能力，而非全部潜在权限。

## Capability

使用 `resource × action × purpose × constraints` 表达：

- resource：对象类型、领域、数据敏感度和可选对象 ID；
- action：`read | derive | create | revise | execute | export | delete | share`；
- purpose：具体目标，不允许“任意未来用途”；
- constraints：时间、次数、目标接收方、风险上限和禁止字段。

默认拒绝；不存在通配的 D3 `read/share` 或任何 D4 能力。

## ConsentRef

事件引用 Consent 时必须固定到具体 revision，并验证：

- 当前时间处于有效期；
- purpose 与事件用途兼容；
- resource/sensitivity/action 未超出 scope；
- Consent 未被 revoked 或 superseded；
- Actor 与受权对象匹配。

## 决策表

| 条件 | 结果 |
|---|---|
| R0、无敏感扩用 | 系统规则可允许 |
| R1、现有明确范围内 | 可由有限周期 Consent 允许 |
| R2、D3 使用或显著计划修改 | 需要明确用户 Consent |
| R3、对外动作/删除/权限改变 | 动作级确认；MVP 不执行外部动作 |
| R4 或 D4 持久化 | 永久拒绝 |
| Consent 缺失、过期、撤销或用途不兼容 | 拒绝且不产生业务状态变化 |

## 最小审计结果

每次授权检查记录 `allowed/denied`、规则版本、匹配的 capability/consent refs 和不含敏感内容的 reason code。

