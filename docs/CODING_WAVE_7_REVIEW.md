# Coding Wave 7 集成评审

状态：本地集成完成；Dart/Flutter 与真机门禁待执行。

## 本轮目标

把 M2 中三个仍停留在接口或 ADR 层的边界推进到可实现、可测试状态：本地事务存储、加密附件生命周期和灾难恢复协议。

## 已集成

### SQLite Vault EventStore

- 通过 driver-neutral `SqlExecutor` 隔离具体 SQLite/SQLCipher 驱动；
- 在单一事务中写入 event log、subject index、projection 和 relay outbox；
- 同 ID 同 canonical 内容幂等，异内容 fail closed；
- 保留 subject revision，并在 read-by-id/read-by-subject 时无损重建；
- 删除事件会预载所有关联对象投影，再执行确定性 reducer；
- D4 在开启事务前拒绝；失败注入测试要求所有 staged writes 回滚。

### Encrypted Blob Engine

- 明文以 stream 进入 crypto port，repository 只接收密文和受限逻辑元数据；
- D4 在订阅输入、创建 key 或开启写事务前拒绝；
- put 失败会 abort partial ciphertext 并销毁新 key；
- delete 先 crypto-erasure，再清理 ciphertext，且支持安全重试；
- adapter 异常被稳定、脱敏错误码包裹，日志不带引用、路径、hash 或密文；
- defensive copy 与 best-effort zeroization 已有 fake-based tests，平台适配器仍须缩短明文生命周期。

### Recovery Protocol v1

- 可信设备迁移优先；离线加密恢复包与分离保存的高熵恢复码兜底；
- Relay、登录密码或服务端配置不能单独解密历史 Vault；
- 恢复先应用 device revocation、account epoch 和 deletion tombstones，再开放业务读取；
- generation 单调递增，旧包、撤销包、重复消费和 security-state rollback 全部 fail closed；
- 12 组无真实秘密的 JSON fixtures 覆盖成功、材料生命周期、错误码非预言机、损坏、撤销、重放与事务失败。

## 本轮验证

- `python3 adapters/sqlite_vault/tool/validate_schema.py`：PASS（SQLite only，未覆盖 SQLCipher）；
- recovery JSON fixtures：全部可解析；
- `git diff --check`：PASS；
- CI shell scripts `bash -n`：PASS。

## 未满足门禁

- 环境无 Dart/Flutter SDK，不能声称 analyze/test/build 已通过；
- 尚无 production SQLCipher driver，也未验证 Android Keystore/StrongBox 行为；
- Recovery crypto suite 仍需安全评审后冻结，synthetic suite 严禁进入生产；
- Redmi Turbo 真机和 Windows 构建/恢复互操作仍未执行。

## 主审结论

Wave 7 可以作为 M2 的本地工程基线，但不能据此退出 M2。下一波优先实现平台 driver composition 与 recovery state machine 的纯 Dart 核心，同时保留真机、SQLCipher 和跨平台互操作为不可跳过的退出门禁。
