# Coding Wave 6 集成评审

日期：2026-08-20  
状态：local static review passed / executable CI pending

## Flutter 完整闭环

- Analyze 与 Feedback 共用同一 EventStore 和 ID generator；
- Task 页面真实调用 complete/skip use cases；
- Review 页面真实写入 create、user_reviewed、accepted/rejected；
- UI 不直接访问 Store，也不暴露 sensitivity 配置；
- 按钮级测试验证事件链与零写入拒绝路径。

## 事件持久化边界

- EventEnvelope 与 Projection 加入严格、版本化 JSON codec；
- D4 encode/decode 永久拒绝；
- 未知 schema、event version、Actor、Sensitivity 和顶层字段失败关闭；
- JSON 键递归排序，UTC 时间、固定 revision 引用和 extensions 可稳定往返；
- payload、integrity、extensions、projection attributes 深层 defensive-copy 并冻结。

## Core 值对象加固

- Revision 与 SchemaVersion 从仅 debug `assert` 改为 release 运行期校验；
- ActorRef 可选标识和 capabilities 全部 nonblank、不可变；
- 全仓库已迁移不再可用的 `const Revision(...)` 调用。

## 密文同步模拟

- In-memory Relay 只依赖 Sync API，只存密文 envelope；
- device→account 注册、账户隔离、账户绑定 cursor 和 envelope 幂等；
- 未注册、跨账户 push/cursor、撤销设备全部失败关闭；
- Trusted-device SyncWorker 负责事件 codec、AAD、seal/open、严格验证与原子 append；
- ACK 必须精确匹配，transport/crypto/decode/append 使用稳定失败码；
- seal/open 后敏感 plaintext buffer best-effort 清零。

## 尚未完成

- 当前 cryptography 只有测试 fake，未选择或实现生产算法套件；
- Relay 只有单进程内存实现；
- 未验证跨进程、断电、重启和真实多设备；
- Dart/Flutter CI 尚未实际运行；
- Wave 2–6 仍因 GitHub 写入额度限制等待远端同步。
