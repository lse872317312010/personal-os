# M1 退出评审

- 评审日期：2026-08-20
- 结论：通过
- 下一阶段：M2 技术选型与总体架构

## 交付检查

| 交付物 | 状态 |
|---|---|
| 核心实体、标识、revision 与引用规则 | accepted |
| Claim/Goal/Plan/Task/Consent/Review 状态机 | accepted |
| append-only 事件信封与事件目录 | accepted |
| Actor、Capability 与 ConsentRef | accepted |
| 确定性投影、迟到事件与幂等 | accepted |
| 并发冲突与显式解决 | accepted |
| 纠错、撤销、删除、tombstone | accepted |
| Snapshot、压缩与保留语义 | accepted |
| Schema/event/projection 演进 | accepted |
| 字段级敏感度与派生继承 | accepted |
| 端到端事件序列与契约测试 | accepted |

## 关键不变量

- 相同有效事件序列产生确定一致的核心状态；
- 业务历史 append-only，纠错通过新事件完成；
- 不使用静默 last-write-wins 解决用户语义；
- D4 永不进入持久对象、事件、日志、错误或 Snapshot；
- Consent 撤销后阻止新的依赖处理；
- 删除不会通过 tombstone、hash、Snapshot 或派生物泄露原内容；
- Schema 升级不创造事实、推断或授权；
- 敏感派生物默认继承最高输入等级。

## 对 M2 的约束

技术方案必须证明：事件持久性、事务边界、幂等写入、投影重建、版本迁移、冲突表示、字段/对象敏感度、删除传播、本地/云端边界和可测试性。不能通过弱化 M1 语义来简化实现。

## 未阻塞债务

- 8 月 17 日对话证据仍需在 M3 前补齐；
- M1 文档是逻辑契约，尚未选择具体 ID、时间、序列化和存储格式；
- 具体加密、备份窗口、同步协议和部署拓扑属于 M2。

