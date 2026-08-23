# ADR-0012 — Sync Envelope Format (v1)

**Status**: accepted
**Date**: 2026-08-23
**Tracks**: A · Core Contract
**Refines**: `packages/sync_api/lib/src/sync_port.dart`（`EncryptedSyncEnvelope`），
`architecture/SYNC_PROTOCOL.md` §"Sync Envelope"

## 背景

`architecture/SYNC_PROTOCOL.md` 在 v0.1 草案里罗列了 Sync Envelope 的
"最小字段集合"，但没有冻结字段名、类型、JSON wire 格式与版本演进规则。
`packages/sync_api/lib/src/sync_port.dart` 已经把这个草案实现成
`EncryptedSyncEnvelope` Dart 类，并被 `packages/sync_engine` 和
`adapters/in_memory_relay` 调用。但因为没有合同化文档：

1. **Relay 实现方没有 wire 格式合同**：未来 Wave 22+ 当真实 Relay
   （如自建 HTTP service 或第三方 relay adapter）落地时，没有文档化的
   JSON wire schema 会导致 Dart ↔ Go / Python / Rust 实现之间字段名
   漂移（snake_case vs camelCase）；
2. **`protocolVersion` 字段语义模糊**：当前代码只是 `int >= 1`，
   没有规定什么时候 bump、什么时候兼容老版本；
3. **与 ADR-0011（Vault Export Envelope）和 ADR-0005（Recovery Package）
   的边界不清**：三者都涉及"账户数据离开本机"，但 sync envelope
   是 Relay 持有的密文流，与 export envelope（明文用户导出）/ recovery
   package（密钥恢复材料）边界必须显式区分；
4. **`accountPseudonym` vs `account_id` 边界**：SYNC_PROTOCOL 写了
   "account pseudonym"，但没说什么时候轮换、被泄露后如何撤销。

本 ADR 冻结 v1 wire 格式 + 字段语义 + 版本演进规则。

## 决定

### 1. Wire 格式：JSON 文档，schema_version = 1

Relay 在 push/pull 接口传输的 envelope 序列化为如下 JSON：

```json
{
  "protocol_version": 1,
  "envelope_id": "<uuid v4 string>",
  "account_pseudonym": "<opaque string, hex or base64url, no business PII>",
  "sender_device_id": "<device id string>",
  "recipient_epoch": "<epoch label string>",
  "sequence": { "first": <int>, "last": <int> },
  "ciphertext_length": <int>,
  "ciphertext": "<base64 string>",
  "signature": "<base64 string>"
}
```

字段约束：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `protocol_version` | int | ✓ | 永远 = 1（v1 wire）。`protocolVersion` 跨大版本不兼容时必须 bump；解析端必须先读 version 再选解析器。 |
| `envelope_id` | string | ✓ | UUID v4，全局唯一。Relay 用它做幂等去重；同一个 envelope_id 重复 push 必须返回相同 receipt，不重复写入。 |
| `account_pseudonym` | string | ✓ | 不含业务 PII 的不透明字符串。同一账户的所有 envelope 共享一个 pseudonym；pseudonym ≠ account_id，**禁止**把邮箱、用户名等放进这个字段。 |
| `sender_device_id` | string | ✓ | 发送设备 ID。必须与 envelope 签名验证通过的 device 公钥对应；签名验证失败必须拒绝。 |
| `recipient_epoch` | string | ✓ | 接收方 epoch 标签。同一账户不同 epoch 的 envelope 互相不可解密；epoch 切换（设备撤销）后老 epoch envelope 在新设备上必须显式拒绝解密。 |
| `sequence` | object | ✓ | `{first: int, last: int}`，`last >= first >= 0`。**仅用于缺口检测**，不参与业务胜负——业务胜负由 event_id 唯一性 + reducer 幂等性决定。 |
| `ciphertext_length` | int | ✓ | 必须等于 base64 解码后 `ciphertext` 字节数；不一致即视为损坏。 |
| `ciphertext` | string | ✓ | base64 编码的密文。Relay 不得尝试解密；只能存储/转发。 |
| `signature` | string | ✓ | base64 编码的设备签名。签名内容是除 `signature` 自身外所有字段的 canonical bytes（详见 §3）。 |

> 任何 envelope 文件缺少上述任一字段 = 拒绝 push / 拒绝 pull 接收。

### 2. 业务字段全部在密文内

以下 M1 业务字段**禁止**出现在 envelope 的明文 JSON 中：

- `event_type`、`object_id`、`subject_id`、`actor_id`
- `occurred_at`、`appended_at`、`schema_version`（事件 schema）
- `sensitivity`、`consent_refs`、`correlation_id`
- 任何 `payload` 字段

业务字段全部在 `ciphertext` 内。Relay 看到的只是"某个设备 X 在 epoch Y
发了序号 N..M 的密文 Z"。这避免 Relay 通过 metadata 推断用户行为模式。

**已知流量分析风险**（SYNC_PROTOCOL §"未决协议点"已记录）：
- `ciphertext_length` 暴露大致事件大小；
- `sequence` 暴露事件频率；
- `account_pseudonym` 长期不变可关联同一账户。

v1 接受这些风险以换取可调试性；v2 评估 padding 与 pseudonym 轮换。

### 3. 签名方案：设备签名密钥 over canonical bytes

签名输入是如下 canonical bytes（不是 JSON 序列化后的字符串——
JSON 字段顺序在不同实现里可能不同）：

```
sha256(
  protocol_version || '|' ||
  envelope_id || '|' ||
  account_pseudonym || '|' ||
  sender_device_id || '|' ||
  recipient_epoch || '|' ||
  sequence.first || ',' || sequence.last || '|' ||
  ciphertext_length || '|' ||
  ciphertext_bytes
)
```

签名算法：Ed25519（v1）。

> Wave 22+ 真实 Relay 实现必须用 Ed25519，不允许退化为 HMAC-SHA256
> （HMAC 需要共享密钥，违反"Relay 不得持有设备私钥"）。
> `adapters/in_memory_relay` 在测试中可以接受任意字节串作为 signature。

### 4. Cursor 是 opaque，不暴露 Relay 内部状态

`OpaqueSyncCursor` 的字符串值由 Relay 自己定义，客户端**禁止**解析
其内部结构。客户端只能在 pull 请求中把上次 receipt 返回的 cursor 原样
传回。这允许 Relay 自由切换实现（SQL row id / timestamp / lamport
counter）而不破坏客户端。

### 5. 与 ADR-0011 Vault Export Envelope / ADR-0005 Recovery Package 的边界

| 维度 | Sync Envelope (本 ADR) | Vault Export (ADR-0011) | Recovery Package (ADR-0005) |
|---|---|---|---|
| 内容 | 密文事件流（per-device 序号） | 明文事件流 + blob 清单 | 加密的密钥恢复材料 |
| 加密 | Ed25519 + account epoch key | 不加密，仅 HMAC 防篡改 | 必须加密，恢复码分离 |
| 谁持有 | Relay（密文） + 接收设备（解密后） | 用户主动导出 → 用户自己保管 | 用户离线保管恢复码 |
| Relay 可见 | envelope metadata（无业务字段） | 不可见（用户直接传文件） | 加密包，恢复码不在其中 |
| 失窃风险 | Relay 失窃 = 密文泄露，无业务数据 | 用户文件失窃 = 明文事件 | 失窃 + 数据备份 = Vault 可解密 |
| 失效条件 | 设备撤销 → 新 epoch key 不分发给撤销设备 | 用户主动销毁文件 | 恢复码销毁 + 旧包撤销 |

**禁止**：
- 在 sync envelope 明文里嵌入任何业务字段（违 §2）；
- 在 sync envelope 里嵌入 Keystore Master Key、Account Epoch Key
  或 Recovery Code 片段（违 ADR-0003 / ADR-0005）；
- 把 sync envelope 当成 export envelope 或 recovery package 使用
  （三者用途不同，混用会破坏安全边界）。

### 6. 版本演进规则

- **新增可选字段**（如 `padding_length`、`sender_device_pubkey_fingerprint`）：
  `protocol_version` 保持 1，解析端必须容忍未知字段（forward-compat）。
- **修改必填字段的语义或类型**：必须 bump `protocol_version` 到 2，
  Relay 必须支持 v1 + v2 并存至少一个 release；客户端在 push 失败时
  可降级回 v1，但不能在不支持 v2 的 Relay 上强推 v2。
- **删除字段**：禁止。改用 `deprecated_<name>: null` 占位。

### 7. Cursor 的版本演进

Cursor 是 opaque，但 Relay 内部实现升级时仍需保持向后兼容：

- Relay 升级后，旧 cursor 字符串必须仍能被解析（哪怕内部换实现）；
- 如果 Relay 必须破坏 cursor 兼容性，必须返回 `cursor_invalidated`
  错误码，让客户端用 `OpaqueSyncCursor.initial()` 从头开始；
- 客户端**禁止**缓存 cursor 超过一个 sync 会话。

## 理由

1. **JSON 而非 Protobuf / MessagePack**：v1 数据量小、调试性强；
   JSON 让 Relay 实现方（可能用 Go / Python / Rust）无需依赖 Dart
   特定 schema 文件。Wave 22+ 真实 Relay 上线后如果流量大，可评估
   切换二进制格式（届时 bump protocol_version = 2）。
2. **`protocol_version` 写在 envelope 里**：很多 sync 协议（如早期
   IMAP）省略版本，结果升级时只能靠"探测字段"猜版本——不可审计。
   本 ADR 强制 version 永远在 envelope 里。
3. **业务字段全部密文**：与 ADR-0003"本地权威加密混合架构"一致——
   Relay 是非权威端，看到的应该是"不可读的字节流"。如果 Relay 能
   看到业务字段，就违反了"Relay 不得独立解密"的边界。
4. **Ed25519 而非 HMAC**：HMAC 需要 Relay 持有共享密钥，违反
   "Relay 不得持有设备私钥"。Ed25519 让 Relay 只持有设备公钥，
   可验签但不可伪造。

## 影响

### 正面
- Wave 22+ 真实 Relay 实现方有 wire 格式合同，不会字段名漂移；
- `EncryptedSyncEnvelope` 类与未来 Relay 实现的边界明确；
- 与 ADR-0011 / ADR-0005 的边界清晰，避免设计混淆。

### 负面
- JSON wire 格式比二进制大 ~30%（base64 编码 + 字段名重复）；
  v1 接受这个开销换取调试性，v2 评估二进制。
- Ed25519 在 Dart 中需要 `package:cryptography` 或 FFI；
  Wave 22+ 必须落地这个依赖。
- `account_pseudonym` 长期不变的流量分析风险——v1 接受，v2 评估轮换。

### 后续行动
1. [Wave 22+] 当真实 Relay 实现落地时，必须实现本 ADR §3 的
   canonical bytes 签名输入（不能用 jsonEncode 输出，因为字段顺序
   不稳定）。
2. [Wave 22+] 落地 Ed25519 签名验证（`package:cryptography` 或
   `package:pinenacl`）；测试 vector 必须包含本 ADR §3 的输入。
3. [M2-Exit] 写 `tool/validate_sync_envelope.py`：给定一份 envelope
   JSON，按本 ADR 校验 protocol_version、字段完整性、
   `ciphertext_length` 一致性、签名重算。

## 未解决问题

1. **`account_pseudonym` 轮换策略**：v1 不轮换；v2 是否在 epoch 切换时
   同时轮换 pseudonym？这会让 Relay 难以关联同一账户的旧/新 envelope，
   但也会让用户调试更难。
2. **批量 envelope 压缩**：v1 一个 envelope = 一段 ciphertext；
   是否需要在 wire 层引入 `batch_envelope`（多个 ciphertext 共享
   metadata）？v1 不做，等流量数据再评估。
3. **Relay 保留期**：envelope 在 Relay 上保留多久？v1 不规定，
   由各 Relay 实现自定；但 ADR-0005 §"备份分离"要求"恢复包"不长期
   存 Relay，sync envelope 是否同等待遇？目前认为 sync envelope
   是"实时同步流"，不是备份，可以保留更短（如 7 天）。

## 参照

- ADR-0003（本地权威加密混合架构）—— envelope 全密文边界依据
- ADR-0005（v1 恢复包）—— envelope ≠ recovery package 边界依据
- ADR-0011（Vault Export Envelope）—— envelope ≠ export envelope 边界依据
- `architecture/SYNC_PROTOCOL.md` §"Sync Envelope"（草案 v0.1）
- `packages/sync_api/lib/src/sync_port.dart`（`EncryptedSyncEnvelope` 类）
- `packages/sync_engine/lib/src/sync_worker.dart`（客户端 sync worker）
- `adapters/in_memory_relay/`（测试用 Relay 实现）
