# Coding Wave 8 集成评审

状态：本地集成完成；真实平台 adapters 与 Dart 执行证据待补。

## 交付

- `packages/recovery`：crypto-agnostic、security-state-first 的单次恢复状态机；
- `adapters/sqlite_vault_driver`：SQLCipher 平台 driver 生命周期与 opaque key lease contract；
- `adapters/device_security`：Android-first、可替换的平台安全 bridge；
- `tool/validate_local_dependencies.py`：无需 Dart SDK 的本地 package path 完整性检查；
- `docs/M2_VERIFICATION_MATRIX.md`：区分 contract、simulation、core implementation 与真机证据。

## 主审修正

1. Relay 可见恢复 envelope 删除 generation/status；generation 只允许在认证解密内层 payload 后出现。
2. 恢复前日志 generation 为 null，旧代次判断移至认证后。
3. device security adapter 对非协议 native 异常同样 fail closed，原始文本和 stack 不越界。
4. RecoverySecret 一旦交给 session，任何前置拒绝、失败或成功路径都必须 best-effort 清零。

## 安全顺序

恢复成功路径固定为：认证包 → 账户绑定 → 新设备绑定 → 校验安全状态 → 应用设备撤销 → 应用 account epoch → 应用删除 tombstones → 原子提交安全状态 → 同步业务密文 → 一致性校验 → 消费旧包并要求轮换 → 开放业务读取。

Vault driver 固定为：获取 opaque key lease → native open → 单事务 allowlisted PRAGMAs + migration → unlocked。Rekey 必须提交新 key 后再销毁旧 lease；失败则保留旧 lease 并销毁 replacement。

## 验证结果

- 本地 dependency graph：PASS（20 manifests、34 path dependencies）；
- SQLite schema smoke：PASS（不包含 SQLCipher）；
- recovery fixtures JSON：PASS；
- shell syntax 与 `git diff --check`：PASS。

新增 fake-based Dart tests 尚未运行：Recovery 8 项、Vault Driver 8 项、Device Security 12 项。环境没有 Dart/Flutter SDK，因此不能把静态存在当作测试通过。

## 下一步

优先补真实 Android bridge/SQLCipher composition spike 和 Redmi Turbo 证据采集；随后用同一 core 做 Windows composition。任何 StrongBox、静态加密或跨平台恢复结论，都只能来自运行时能力与可复现实验。
