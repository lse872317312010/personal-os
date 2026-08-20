# Recovery Protocol v1

状态：M2 executable design；密码学算法套件尚未冻结，不能据此宣称恢复功能可用。

本协议把 [ADR 0005](../docs/decisions/0005-v1-recovery-strategy.md) 转换为可实现、可互操作和可测试的约束。规范中的 `MUST / MUST NOT / SHOULD` 分别表示强制、禁止和推荐。

## 1. 安全目标与非目标

v1 必须同时支持：

1. 已解锁 Trusted Device 向新设备迁移；
2. 所有 Trusted Device 不可用时，以“加密恢复包 + 与其分离保存的高熵恢复码”恢复；
3. Relay、登录密码、短信、邮箱验证或单一服务端凭据均不能独立解密 Vault；
4. 恢复期间先应用设备撤销和 deletion tombstone，再开放任何业务读取；
5. 旧包、已撤销包、重复恢复、回滚的安全状态必须 fail closed。

v1 不提供服务端 escrow、社交恢复、门限恢复，也不承诺撤回丢失设备此前已经读取或导出的明文。

## 2. 参与者与信任边界

- **Recovery Client**：在隔离的锁定态执行恢复的新设备。
- **Trusted Device**：可批准迁移的已解锁设备。
- **Relay**：不可信的可用性服务，只保存密文对象与有限路由元数据。
- **Security State Feed**：经账户授权签名、单调递增的 device revocation、account epoch 与 deletion tombstone 集合。
- **Recovery Code**：用户离线持有的高熵秘密；不得上传 Relay、写入日志或遥测。

Relay 被假定可以读取、替换、删除、重放和回滚其保存的任意对象。协议不隐藏访问时序和近似密文尺寸；需要通过 size class/padding 降低精确尺寸泄露。

## 3. Versioned encrypted recovery package

### 3.1 外层 envelope

下列字段是 Relay 可见的完整上限。实现不得在外层加入账户 ID、设备 ID、key ID、epoch、恢复代次、邮箱、手机号或业务标识。

```json
{
  "object_type": "personal-os.recovery-package",
  "format_version": 1,
  "package_id": "random-128-bit-or-more-opaque-id",
  "suite": {
    "suite_id": "REGISTRY-SLOT",
    "kdf_parameters": "suite-defined-opaque-object",
    "aead_parameters": "suite-defined-opaque-object"
  },
  "ciphertext": "base64url-without-padding",
  "size_class": "suite-defined-bucket"
}
```

约束：

- `package_id` MUST 随机生成且不得由账户或设备标识确定性派生。
- `format_version` 只描述 envelope 语法；密码学选择由 `suite_id` 指向独立、版本化、不可变的 suite registry 条目。
- `kdf_parameters` 与 `aead_parameters` 是预留槽。M2 不虚选 KDF、AEAD、参数、nonce 长度或恢复码编码；生产实现必须在安全评审冻结 suite 后才能启用。
- 未识别或已退役的 suite MUST 返回 `RECOVERY_SUITE_UNSUPPORTED`，不得尝试降级。
- envelope 中除 `ciphertext` 外的安全相关字段 MUST 作为 AEAD associated data 被认证。
- Relay 可另存传输所需的 blob locator、ETag 和粗粒度 size class，但这些不是可信输入。

fixtures 使用 `TEST-ONLY-SYNTHETIC-v1`。它只驱动状态机与错误码测试，不代表任何密码学算法，生产构建 MUST 拒绝该 suite。

### 3.2 加密内层 payload

成功认证解密后才能得到：

```text
payload_schema_version
account_binding_commitment
recovery_generation
created_at
expires_at | null
wrapped_account_key_material[]
minimum_account_epoch
security_state_anchor { revision, digest, signing_key_id }
device_revocation_cursor
deletion_tombstone_cursor
rotation_reason
```

要求：

- 不得包含可直接使用的明文长期密钥；所有账户/epoch 材料仍须按 suite 的内层封装规则包装。
- `account_binding_commitment` 用于解密后的账户一致性校验，不得出现在 Relay 可见元数据中。
- `recovery_generation` 对每次轮换严格递增；客户端须以本地可信记录和已签名 Security State Feed 检测旧包。
- 包不能作为安全状态的最终真相。包中的 anchor/cursor 只定义恢复后必须追赶的下限。

## 4. 生命周期状态机

### 4.1 恢复材料

```text
not_configured
  -> generated_unverified
  -> recovery_ready
  -> rotation_required
  -> revoked
```

| 当前状态 | 操作 | 下一状态 | 强制条件 |
|---|---|---|---|
| `not_configured` | create | `generated_unverified` | 生成新 recovery generation；恢复码仅显示给用户 |
| `generated_unverified` | verify | `recovery_ready` | 在隔离流程中完成一次真实认证解密；不得只比较字符串或 checksum |
| `generated_unverified` | revoke | `revoked` | 删除可删除副本并发布撤销记录 |
| `recovery_ready` | require rotation | `rotation_required` | 设备新增/撤销、疑似泄露、恢复成功、格式或 suite 升级 |
| `rotation_required` | rotate + verify | `recovery_ready` | generation 递增，新包验证成功后原子激活 |
| 任意非终态 | revoke | `revoked` | 撤销记录先持久化；包删除是后续清理，不是撤销成立条件 |

旧 generation 在新包激活后为 `superseded`，即使 Relay 重放也必须拒绝。`revoked` 为终态，不能恢复为 ready。

### 4.2 Restore session

```text
intake
 -> envelope_validated
 -> package_authenticated
 -> account_verified
 -> device_bound
 -> security_state_syncing
 -> security_state_applied
 -> vault_data_syncing
 -> consistency_verified
 -> unlocked
```

任一步骤失败进入 `failed`；只有重新创建独立 session 才能重试。状态不可后退，`unlocked` 与 `failed` 均为终态。

关键门禁：

- `package_authenticated` 前，错误恢复码与密文/标签损坏对外统一为 `RECOVERY_AUTH_FAILED`。
- `device_bound` 只建立新 Device Identity，不授予业务读取能力。
- 在 staging store 中先验证 Security State Feed 的签名、账户绑定、单调 revision 和 anchor 下限。
- MUST 先应用 device revocation，再应用最新 account epoch，再应用 deletion tombstone；任一失败不得进入 `vault_data_syncing`。
- 业务事件/Blob 可以下载为密文，但在 `security_state_applied` 前不得解封业务 key、建立可读投影或向 UI/模型暴露内容。
- 一致性验证必须证明被撤销设备不能取得新 epoch key、已删除对象没有可读 key/投影、Security State revision 不低于包内 anchor。
- 进入 `unlocked` 后立即触发恢复材料轮换；旧包不可再次恢复。

## 5. 操作协议

### Create / Verify

1. 创建高熵恢复码与新 generation 的恢复材料。
2. 以冻结 suite 生成 envelope；敏感字段只进入密文 payload。
3. 持久化为 `generated_unverified`，显示永久丢失风险。
4. 用户在隔离验证流输入恢复码，客户端执行完整认证解密与 account binding 校验。
5. 成功后原子写入 `recovery_ready` 和不含秘密的审计事件。

### Rotate / Revoke

1. 先将现有 generation 标记 `rotation_required` 或 `revoked`。
2. 若因设备撤销触发，先发布 device revocation 并开启新 Account Epoch。
3. 创建并验证更高 generation 的包。
4. 原子激活新包并把所有更低 generation 标为 `superseded`。
5. Relay 删除旧 blob 只是 best-effort；客户端拒绝旧 generation 才是安全边界。

### Trusted Device migration

迁移复用相同的 `device_bound -> security_state_syncing -> ... -> unlocked` 后半状态机。已解锁设备通过双方可见的带外确认绑定新 Device Identity，并为其封装当前 epoch 材料；迁移不得绕过撤销、墓碑和一致性门禁。

### Offline restore

客户端必须同时获得数据备份、envelope 和恢复码。服务端身份验证只可定位密文对象，不可替代恢复码。恢复成功记录 `package_id`/generation 的一次性消费，并要求轮换；相同或更旧包再次使用返回稳定拒绝码。

## 6. 稳定错误码

| Error code | 条件 | 是否可重试 |
|---|---|---|
| `RECOVERY_PACKAGE_MALFORMED` | envelope 缺字段、类型或编码非法 | 换包 |
| `RECOVERY_FORMAT_UNSUPPORTED` | format/payload schema 不支持 | 升级客户端 |
| `RECOVERY_SUITE_UNSUPPORTED` | suite 未识别、测试专用或已退役 | 升级/换包 |
| `RECOVERY_AUTH_FAILED` | 恢复码错误、ciphertext/tag/AAD 损坏 | 重新输入或换包；不细分原因 |
| `RECOVERY_ACCOUNT_MISMATCH` | 解密后账户绑定不一致 | 换正确账户/包 |
| `RECOVERY_PACKAGE_REVOKED` | generation/package 明确撤销 | 不可 |
| `RECOVERY_PACKAGE_SUPERSEDED` | 低于已知有效 generation | 不可 |
| `RECOVERY_ALREADY_CONSUMED` | 已成功使用的 package/session 被重放 | 不可 |
| `RECOVERY_MATERIAL_UNVERIFIED` | 包已生成但用户尚未完成持有验证 | 完成验证或重新创建 |
| `RECOVERY_DEVICE_BINDING_FAILED` | 新 Device Identity 绑定失败 | 新 session |
| `SECURITY_STATE_UNAVAILABLE` | 无法取得满足 anchor 的安全状态 | 稍后重试，保持锁定 |
| `SECURITY_STATE_SIGNATURE_INVALID` | 签名或账户绑定无效 | 不可，安全告警 |
| `SECURITY_STATE_ROLLBACK` | revision/epoch 低于已知值或 anchor | 不可，安全告警 |
| `DEVICE_REVOCATION_APPLY_FAILED` | 撤销列表不能原子应用 | 新 session，保持锁定 |
| `DELETION_TOMBSTONE_APPLY_FAILED` | 墓碑不能原子应用 | 新 session，保持锁定 |
| `RECOVERY_CONSISTENCY_FAILED` | 最终不变量不满足 | 新 session，保持锁定 |

日志只允许记录 error code、package_id、generation、session_id、状态与时间；MUST NOT 记录恢复码、KDF 输入、key material、明文 payload、ciphertext 全文或用户数据。

## 7. 服务端不可单独解密不变量

给定 Relay 数据库、登录凭据、envelope、全部加密事件/Blob 和服务端配置，测试主体仍缺少 Recovery Code 或 Trusted Device 私钥，必须无法得到 package payload、Vault key 或业务明文。服务端不得提供“重置恢复码后解密旧 Vault”的接口。

这是一项架构不变量，不以 fixtures 中的合成字符串作为密码学证明。冻结 production suite 后还必须执行已知答案测试、跨 Android/Windows 互操作测试、错误码非预言机测试和破坏性恢复演练。

## 8. 审计事件

至少记录：`recovery.package_created`、`recovery.material_verified`、`recovery.rotation_required`、`recovery.package_rotated`、`recovery.package_revoked`、`recovery.session_started`、`recovery.security_state_applied`、`recovery.completed`、`recovery.failed`。事件 payload 只能包含非秘密标识、代次、状态、原因码和时间。

## 9. 可执行测试入口

规范性测试矩阵见 [`test_contract/RECOVERY_TESTS.md`](../test_contract/RECOVERY_TESTS.md)，语言中立 fixtures 位于 [`fixtures/recovery/`](../fixtures/recovery/)。fixtures 不含真实 secret、key、nonce、tag 或真实密文，不能用于实现密码学。
