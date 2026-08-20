# 密钥管理草案 v0.2

状态：proposal；具体算法套件在安全评审后冻结

## 密钥层级

1. Device Identity Key：设备签名身份；
2. Device Wrapping Key：由 OS Keystore/Keychain 保护，用于解封本地密钥；
3. Vault Master Key：派生数据库、索引和本地元数据密钥；
4. Blob Key：每对象随机密钥，便于独立删除和分享控制；
5. Account Epoch Key：同步包加密，设备撤销/成员变化时轮换；
6. Recovery Key：高熵恢复码保护的恢复材料，不能与恢复码存于同一设备同一保护域。

## 原则

- 应用代码、仓库、配置、日志和 Relay 不含明文长期密钥；
- OS-backed key 尽量不可导出，并可要求设备解锁/生物认证；
- 不用用户登录密码直接作为数据库密钥；
- key ID、版本和用途可审计，但不记录密钥材料；
- Blob 删除优先销毁 Blob Key，再清理密文与副本；
- 撤销设备触发新 epoch，只保护未来数据；
- 密钥轮换不改变事件 ID 或业务历史。

## v1 恢复策略

v1 冻结为“可信设备迁移优先，离线用户恢复包 + 高熵恢复码兜底”的组合，详见 [ADR 0005](../docs/decisions/0005-v1-recovery-strategy.md)。

- Android Primary Vault 可将密钥材料封装给经带外确认的新设备；future Windows Trusted Device 可承担同类迁移；
- 无可信设备可用时，用户必须同时提供加密恢复包和与其分离保管的恢复码；
- Relay 可以保存加密恢复包，但不得拥有恢复码或任何可单独解密完整 Vault 的能力；
- 登录密码、短信、邮箱验证或服务端重置不能代替恢复码；
- v1 不采用服务端 escrow、社交恢复或门限份额恢复。

### 创建与状态

恢复材料状态至少区分 `not_configured / generated_unverified / recovery_ready / rotation_required / revoked`。只有恢复包完整性和用户持有恢复码经过验证后才能进入 `recovery_ready`；生成但未验证时必须持续显示永久丢失风险。

### 轮换与撤销

- 新增/撤销 Trusted Device、成功恢复、怀疑恢复码泄露或格式/算法升级时更新恢复包；
- 怀疑恢复码泄露时轮换 Recovery Key；撤销设备时同时开启新 Account Epoch；
- 旧恢复包必须带版本与状态并被拒绝，不能静默降级；
- 轮换保护未来数据，不承诺收回已经解密或外泄的历史数据。

### 恢复验证顺序

1. 校验恢复包格式、版本、完整性和恢复码；
2. 绑定新的 Device Identity，并记录不含秘密的审计事件；
3. 恢复密钥后同步并验证设备撤销、最新 epoch 和 deletion tombstone；
4. 完成一致性检查后才开放业务数据读取；
5. 恢复成功后轮换恢复材料，避免旧包持续有效。

## 备份

备份必须包含加密事件、Blob、Schema/epoch 元数据和删除状态。数据备份、加密恢复包与恢复码是三个独立对象：恢复码至少与手机、恢复包和数据备份分离保管。恢复后先应用设备撤销和 deletion tombstone，再开放业务读取。

若全部 Trusted Device 丢失，且数据备份、恢复包、恢复码的必要组合有任一缺失或损坏，数据可能永久不可恢复；系统和服务端不得提供绕过手段。

## 尚未完成

以上是冻结的 v1 策略，不代表实现已完成。仍需定义恢复包 wire format、具体密码学套件、Android/Windows 安全存储适配、端到端迁移与破坏性恢复测试，并通过安全评审。
