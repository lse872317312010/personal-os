# personal_os_events

Personal OS 的纯 Dart 事件核心包，依赖 `personal_os_domain`，不依赖 Flutter 或平台插件。

当前骨架提供：

- M1 append-only `EventEnvelope`；
- 独立 `eventVersion`、现实发生时间与审计记录时间；
- Actor、subject/source/Consent refs、敏感度、payload、integrity；
- `extensions` 用于保留未知非关键顶层字段；
- 确定性 reducer，覆盖 M1 S1/S2 的 Source、Observation、Baseline、Opportunity、Recommendation、Execution、Outcome 及既有生命周期；
- 支持删除 barrier/安全 tombstone 的最小投影，以及规范已定义的显式 Conflict 生命周期；
- event ID 幂等、expected revision 检查、未知版本隔离和稳定拒绝 reason code；
- `EventEnvelopeJsonCodec` / `ObjectProjectionJsonCodec` 提供 schema v1 严格 JSON 边界：
  递归键排序保证确定输出，时间强制显式 UTC，未知字段、版本与安全枚举 fail-closed；
- 未知非关键数据只能显式放入 `extensions`，D4 永久禁止持久化编码和解码；
- Event payload/integrity/extensions 与投影 attributes 在构造时递归复制并冻结，调用方无法通过原集合或嵌套引用改写历史；
- `task.completed` 对 ExecutionRecord 引用的最小不变量检查。

## 有意留在外层的能力

授权与 Consent 有效性、D4 拒绝、敏感度传播、不可交换冲突、迟到事件区间重投影、Snapshot 和 schema upcaster 由后续 `policy`、`application` 与存储投影实现。这个 reducer 不会假装已经执行这些检查。

`task.ready`、`task.in_progress`、`review.user_reviewed` 已由 M1 S2 固定，现纳入 reducer。`goal.completed` 按状态机投影为 `achieved`。

仍由上层 runner/policy 明确隔离：撤销 Consent 后的派生拒绝、迟到事件区间重投影，以及“迟到 Constraint 使历史批准失效”的领域判断。Reducer 不会仅凭时间戳猜测这些语义。

当前环境没有 Dart 工具链，本包尚未执行 `dart analyze` 或测试；代码仅完成结构与人工审查。
