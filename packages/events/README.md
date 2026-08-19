# personal_os_events

Personal OS 的纯 Dart 事件核心包，依赖 `personal_os_domain`，不依赖 Flutter 或平台插件。

当前骨架提供：

- M1 append-only `EventEnvelope`；
- 独立 `eventVersion`、现实发生时间与审计记录时间；
- Actor、subject/source/Consent refs、敏感度、payload、integrity；
- `extensions` 用于保留未知非关键顶层字段；
- 最小确定性 reducer，覆盖首批 Claim、Goal、Plan、Task、Consent、Review 生命周期；
- event ID 幂等、expected revision 检查、未知版本隔离和稳定拒绝 reason code；
- `task.completed` 对 ExecutionRecord 引用的最小不变量检查。

## 有意留在外层的能力

授权与 Consent 有效性、D4 拒绝、敏感度传播、不可交换冲突、迟到事件区间重投影、Snapshot 和 schema upcaster 由后续 `policy`、`application` 与存储投影实现。这个 reducer 不会假装已经执行这些检查。

规范中尚未定义 `task.ready`、`task.in_progress`、`review.user_reviewed` 的首批事件名，因此状态已建模，但本 reducer 不自行发明持久事件类型。`goal.completed` 按状态机投影为 `achieved`。

当前环境没有 Dart 工具链，本包尚未执行 `dart analyze` 或测试；代码仅完成结构与人工审查。

