# Recovery protocol contract tests

状态：M2 executable test design。规范来源：[`architecture/RECOVERY_PROTOCOL.md`](../architecture/RECOVERY_PROTOCOL.md)。

## Runner contract

候选命令：

```text
recovery-contract-test --fixtures fixtures/recovery --adapter <adapter-name>
```

Runner MUST：

1. 校验所有 `rc*.json` 满足 `recovery-fixture.schema.json`；
2. 把 fixture 中的值视为惰性标签，只调用协议模拟器，不调用生产密码学；
3. 精确比较 `result`、`error_code`、终态和状态顺序；
4. 断言 rejected/blocked case 从未进入 `security_state_applied`、`vault_data_syncing` 或 `unlocked`，除非 fixture 明确在更晚门禁失败；
5. 捕获日志并拒绝 recovery code、ciphertext、KDF 输入、key material 或 payload 的复制；
6. 同一 fixture 连续运行两次，状态与错误码确定一致；
7. production adapter 遇到 `TEST-ONLY-SYNTHETIC-v1` 必须返回 `RECOVERY_SUITE_UNSUPPORTED`；测试模拟器才可解释合成标签。

fixtures 是控制流证据，不是密码学已实现或安全性的证明。

## Test matrix

| ID | Fixture / setup | Required result |
|---|---|---|
| RCT-001 | `rc001_success_security_first.json` | 顺序必须为 revocation → epoch → tombstone → `security_state_applied` → data → unlock |
| RCT-002 | `rc002_wrong_code.json` | `RECOVERY_AUTH_FAILED`；无 key import、无业务读取 |
| RCT-003 | `rc003_corrupted_ciphertext.json` | 与 RCT-002 相同公开错误和可观察状态，避免 oracle |
| RCT-004 | `rc004_superseded_package.json` | `RECOVERY_PACKAGE_SUPERSEDED`；不得因 Relay 仍保存旧包而接受 |
| RCT-005 | `rc005_revoked_package.json` | `RECOVERY_PACKAGE_REVOKED`；revoked 不可重新激活 |
| RCT-006 | `rc006_duplicate_restore.json` | `RECOVERY_ALREADY_CONSUMED`；不重复授予设备或复用 session |
| RCT-007 | `rc007_unsupported_version.json` | `RECOVERY_FORMAT_UNSUPPORTED`；不得降级，不处理恢复码 |
| RCT-008 | `rc008_relay_alone.json` | 服务端数据与登录凭据不能产出 package payload、Vault key 或业务明文 |
| RCT-009 | `rc009_security_state_rollback.json` | `SECURITY_STATE_ROLLBACK`；包已认证也必须保持锁定 |
| RCT-010 | `rc010_tombstone_apply_failure.json` | `DELETION_TOMBSTONE_APPLY_FAILED`；staged keys 不提交 |
| RCT-011 | `rc011_material_lifecycle.json` | create → verify → rotate → revoke 顺序确定，generation 严格递增 |
| RCT-012 | `rc012_unverified_material.json` | `RECOVERY_MATERIAL_UNVERIFIED`；generated 不得等同 ready |

## Lifecycle tests without secret fixtures

| ID | Initial state | Action | Expected |
|---|---|---|---|
| RCT-101 | `not_configured` | create | `generated_unverified`，不得显示 ready |
| RCT-102 | `generated_unverified` | full isolated verify | `recovery_ready`，产生无秘密审计事件 |
| RCT-103 | `generated_unverified` | checksum/string-only verify | 拒绝，状态不变 |
| RCT-104 | `recovery_ready` | trusted device revoked | 先发布 device revocation、新 epoch，再进入 `rotation_required` |
| RCT-105 | `rotation_required` | rotate generation N→N+1 and verify | 新包 ready，N 原子变为 superseded |
| RCT-106 | 任意非终态 | revoke | `revoked`；Relay 删除失败也不可恢复 |
| RCT-107 | `revoked` | verify/activate | 拒绝；终态不变 |
| RCT-108 | `unlocked` after recovery | finalize | 旧 package 标为 consumed，并触发 rotation required |

## Envelope and opacity tests

- RCT-201：外层只允许 protocol 定义字段；出现 account/device/key/epoch/email/phone 标识即失败。
- RCT-202：`package_id` 至少 128 bit 随机性来源，且不由账户标识确定性派生。
- RCT-203：修改任一被认证的外层字段必须导致 `RECOVERY_AUTH_FAILED`。
- RCT-204：未知/退役 suite 返回 `RECOVERY_SUITE_UNSUPPORTED`，无 fallback。
- RCT-205：format 与 payload schema 分别版本化；未知版本不可猜测解析。
- RCT-206：Relay 列表接口只返回 opaque locator、format、suite、粗粒度 size class；不返回内层字段。
- RCT-207：审计与错误日志扫描不得命中 fixture 的 `recovery_code`、envelope 内容或 secret-derived diagnostic。

## Security-first restore gates

每个 restore adapter 都必须注入故障并验证：

- device revocation 获取失败、签名失败或原子应用失败；
- account epoch 回滚；
- deletion tombstone 获取失败、签名失败或原子应用失败；
- ciphertext 数据已下载但 security state 未完成；
- consistency check 发现 deleted object 仍有可读 key；
- consistency check 发现 revoked device 仍得到当前 epoch key。

以上任一情况都必须保持 Vault locked、丢弃 staged key state，并产生不含秘密的稳定 error code。

## 后续密码学验收（suite 冻结后）

当前测试明确不选择 KDF/AEAD。安全评审冻结 suite registry 后，必须新增：

- 官方/独立 known-answer vectors；
- KDF 参数上下界与资源消耗测试；
- nonce/IV 唯一性和随机源故障测试；
- AEAD ciphertext、tag、AAD 各字段篡改测试；
- Android 与 Windows 双向恢复包互操作；
- 相同外部错误下的时间与日志侧信道检查；
- 全新设备、旧设备丢失、Relay 回滚、离线备份损坏的破坏性演练。

这些通过前，UI 和文档不得声称“恢复已可用”。
