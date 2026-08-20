# security_api

纯 Dart、平台无关的 Vault 安全能力边界，对齐
`architecture/KEY_MANAGEMENT.md`。本包定义契约，不实现密码学。

## 边界

- `VaultSession`：显式 lock/unlock，过期授权 fail-closed。
- `SecureUnlockPort`：对接 Android Keystore、生物认证、Windows Hello 等；
  Core 只获得短期 `UnlockGrant`。
- `KeyProvider`：创建、wrap/unwrap、epoch rotate、device revoke、销毁密钥。
- `SecurityErrorCode`：稳定 wire value，可用于日志与跨适配器判断。

`KeyHandle` 只是不可导出的引用，`unwrapKey` 也只返回 handle。接口刻意不提供
明文密钥导出能力；应用、日志、配置、Relay 和测试均不得持有 raw secret。
`WrappedKey.ciphertext` 只能承载由平台适配器产生的加密 envelope。

设备撤销必须在成功返回前完成 Account Epoch 轮换。撤销只保护未来数据，
`authorizeNewData` 对已撤销设备必须拒绝；历史密文的处理不在此接口中伪装成
可追溯撤销。

## 适配器要求

1. 长期密钥由 OS-backed protection domain 或等价安全设施持有；
2. 校验 grant 有效性、key purpose、版本和 wrapping relationship；
3. wrap/unwrap、rotate/revoke 必须原子或 fail-closed；
4. 错误信息只能包含安全元数据，不得包含密钥材料；
5. 不得为方便调试添加 `exportKey`、`rawBytes` 等 API。

运行测试：`dart test packages/security_api`。
