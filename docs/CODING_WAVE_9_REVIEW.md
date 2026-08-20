# Coding Wave 9 集成评审

状态：本地集成完成；真机 runbook 尚未执行。

## 交付

- `packages/runtime`：Vault、EventStore、Model 与 Sync 的 fail-closed 生命周期编排；
- `tool/contract_audit`：恢复规范与 fixtures 的标准库一致性审计器及 8 项 Python tests；
- `evidence/android`：Redmi Turbo 九场景 runbook、严格 evidence schema、synthetic record 和安全辅助脚本；
- `tool/check_contracts.sh` 与 Repository Contracts CI。

## Runtime 顺序

- 解锁：Vault → EventStore available → Model enabled → Sync started；
- 锁定/失败回滚：Sync stopped → Model disabled → EventStore unavailable → Vault locked；
- 后台：停止 Sync 与 Model，但保留已解锁的本地 Vault；
- 返回前台失败：执行完整逆序清理并回到 locked；
- close 是不可逆终态。

## 已执行验证

- Recovery contract audit：PASS；
- Python audit tests：8/8 PASS；
- Android synthetic evidence validation：PASS；
- Local dependency graph：21 manifests / 34 path dependencies PASS；
- SQLite schema smoke：PASS（不包含 SQLCipher）；
- shell syntax 与 `git diff --check`：PASS。

Runtime 新增 9 项 Dart tests，但环境没有 Dart SDK，未实际执行。

## Redmi Turbo 证据边界

真机流程覆盖安装启动、离线、锁屏、重启、能力报告、wrong-key、可信设备恢复、离线包恢复与设备撤销。工具不得读取或保存序列号、Android ID、build fingerprint、日志正文、文件名、通知内容、生物特征或用户内容；示例记录明确是 synthetic/blocked，不能冒充真机通过。
