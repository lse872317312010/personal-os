# Coding Wave 4–5 集成评审

日期：2026-08-20  
状态：local static/schema validation passed / Dart & Flutter execution pending

## 完整行动反馈闭环

Application 新增：

- `execution.recorded → task.completed` 单批原子写入；
- `task.skipped` 强制记录原因；
- `review.created → review.user_reviewed → review.accepted|rejected`；
- Review 决策只能由 User Actor 完成；
- 四个反馈入口在分配 ID、构造事件或访问 Store 前永久拒绝 D4。

## SQLite Vault Schema v1

Schema 已覆盖 event log、subjects、projections、outbox、blob metadata、Consent revisions、deletion tombstones 与 propagation log。

主审修正：

- 删除可重识别 `target_id_digest`，改为随机不可关联 `target_token`；
- Blob 只保存 `ciphertext_digest`，禁止明文内容摘要；
- Tombstone 保持不可变，传播进度使用独立 append-only log；
- D4 由数据库 CHECK 再次拒绝；
- event、projection、outbox 的原子事务 smoke test 已通过。

验证结果：`sqlite_vault schema v1: PASS (SQLite only; SQLCipher not exercised)`。

## 模型与 Flutter 边界

- Synthetic model 已移出 UI，成为独立 `adapters/model_fixture`；
- 只接受 `blob://` opaque ref，不读取文件、图片字节或网络；
- Flutter composition 不再定义或伪造模型结论。

## Blob 与同步边界

- Blob 改为流式读写、受限 metadata、幂等 delete 和脱敏 BlobRef；
- D4 不存在授权例外，任何 Consent/Actor/配置都不能允许 D4 Blob；
- Relay-facing `SyncPort` 不再接触 EventEnvelope，只接受密文 envelope；
- Cursor、密文和签名 defensive-copy，诊断输出脱敏；
- 业务事件编码/解密仅存在于可信设备侧 SyncWorker 边界。

## 仍未完成

- 真实 SQLite driver 与 SQLCipher keying；
- Android Keystore adapter；
- 本地 SyncWorker、密文算法套件与 Relay；
- GitHub Actions 首次真实运行；
- Redmi Turbo 真机验证。
