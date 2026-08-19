# In-memory adapter

状态：M2 candidate，仅用于 Core 契约测试、桌面/手机原型和持久化适配器的行为基准，不是生产持久化方案。

## 已冻结的候选语义

- 单个或批量 append 先在 staging state 中完成 reducer 校验，再一次性提交；任一事件失败时 Event Log、Projection、seen IDs、序号和 Outbox 均不变化。
- `event_id` 已存在或在同一批次重复时视为幂等成功，不产生第二条事件、投影变化或 Outbox 项。
- `expected_revision` 不匹配时返回 `revisionConflict`，整批拒绝。
- Event Log 和 Outbox 使用 adapter 分配的单调 sequence 确定读取顺序，不依赖设备时钟。
- 每个新提交事件恰好创建一个待确认 Outbox 项；确认操作幂等。
- reducer 拒绝或隔离的事件当前均导致存储事务失败。未来若引入 quarantine log，必须作为独立明确接口，不能静默混入主日志。

## 待 `storage_api` 稳定后对接

`InMemoryEventStore` 已实现 `personal_os_storage_api.EventStore`，Application 可通过正式 Port 注入；同步的 `appendTransaction` 只为 adapter 测试和 spike 暴露详细结果。仍待正式持久化 adapter 对接以下等价能力：

- `append(events, expected revision semantics) -> commit/conflict/invalid`；
- 按 durable sequence 分页读取事件；
- 按对象引用读取当前 Projection；
- 按 sequence 拉取及确认 Outbox；
- 由 SQLite/SQLCipher adapter 提供等价事务边界和重启后持久性。

并发边界：该候选实现仅保证单 Dart isolate 内同步调用的原子性。跨 isolate 或进程并发必须由正式持久化 adapter 的事务与唯一约束保证。

## 验证

安装 Dart SDK 后在本目录执行：

```sh
dart pub get
dart test
```
