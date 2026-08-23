# ADR-0011 — Vault Export Envelope Format (v1)

**Status**: accepted
**Date**: 2026-08-23
**Tracks**: A · Core Contract
**Refines**: Wave 17a (`packages/storage_api/lib/src/vault_exporter.dart`)

## 背景

Wave 17a 交付了 `VaultExporter`：一个纯 Dart 打包器，把当前 Vault 的事件
序列（以及未来 Wave 18 的 blob 元数据清单）封装成一个可签名、可哈希、
可离线验证的 envelope。`ExportScreen`（Wave 19b）已经把它接进 UI，
让用户可以在删除 Vault 之前生成 export 文件并验证 SHA-256 摘要。

但是 Wave 17a 只在源代码注释里写了 envelope 格式，没有正式 ADR。
这意味着：

1. 第三方 reviewer 拿到一份 export 文件时，无法判断它是不是合规的
   Personal OS v1 export——因为没有文档化的 schema_version 升级政策；
2. 未来 Wave 22+ 想加新的字段（如 `key_epoch_id`、`device_binding`）时，
   没有合同来约束"什么时候 bump schema_version、什么时候向后兼容"；
3. 与 ADR-0010（evidence ledger SHA-256 链）和 ADR-0005（恢复包分离
   原则）之间的边界没有写清，容易混淆"export envelope"和
   "recovery package"——前者是用户主动导出的明文快照，后者是
   ADR-0005 定义的账户密钥恢复材料。

本 ADR 冻结 envelope v1 的字段、签名方案、版本演进规则，并明确
它和 recovery package 的关系。

## 决定

### 1. Envelope 是单一 JSON 文档，schema_version = 1

格式如下（所有 UTF-8、所有 JSON、单文档）：

```json
{
  "schema_version": 1,
  "exported_at": "2026-08-23T12:00:00.000Z",
  "composition_mode": "demo|devSqlite|prodEncrypted",
  "events": [ ...EventEnvelopeJsonCodec.encode() 输出... ],
  "blob_manifest": [ { "ref":"...", "media_type":"...", "byte_length":N,
                       "sha256_hex":"..." }, ... ],
  "event_count": N,
  "blob_count":  M,
  "passphrase_challenge": "<hex sha256(passphrase)>" | null
}
```

字段约束：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `schema_version` | int | ✓ | 永远 = 1。未来不兼容变更必须 bump 到 2，并保留 v1 解析器至少一个 release。 |
| `exported_at` | RFC3339 UTC | ✓ | `DateTime.toIso8601String()`，恢复端必须接受带或不带毫秒的形式。 |
| `composition_mode` | enum string | ✓ | 必须是 `"demo"`、`"devSqlite"`、`"prodEncrypted"` 三者之一；其他值恢复端必须拒绝。 |
| `events` | array | ✓ | EventEnvelope JSON 列表；空 Vault 导出 = `[]`。 |
| `blob_manifest` | array | ✓ | 元数据清单；Wave 17a 始终为 `[]`，Wave 18 起可能填充。 |
| `event_count` | int | ✓ | 必须等于 `events.length`，否则视为损坏。 |
| `blob_count` | int | ✓ | 必须等于 `blob_manifest.length`。 |
| `passphrase_challenge` | string\|null | ✓ | 用户设了 passphrase 时 = `sha256(passphrase).toHex()`；未设时 = `null`。 |

> 任何 envelope 文件缺少上述任一字段 = 拒绝恢复。

### 2. 签名方案：HMAC-SHA256，detached

envelope 的"签名"不在 JSON 文档里。它是 HMAC-SHA256 over the exact UTF-8
bytes of the JSON document，作为 detached hex 字符串单独保存（恢复端 UI
会展示 `signatureHex`，用户可手动比对）。

签名密钥的选取规则：

- 用户设了 passphrase：`key = utf8_encode(passphrase)`
- 用户未设 passphrase：`key = utf8_encode("personal-os-vault-export-dev-signing-seed-v1")`

> **明确：HMAC 不是 SQLCipher 替代品。** 这个签名只防"传输中意外截断 / 篡改"。
> 真实加密保护由 ADR-0007 的存储栈负责；export envelope 默认是**明文 JSON**
> 事件流，跟 ADR-0003 的"本地权威加密混合架构"无冲突——因为导出动作
> 本身就是用户主动选择"把数据搬离加密边界"，这一刻用户掌握着数据。

### 3. 摘要方案：SHA-256 over the bytes

`sha256Hex = sha256(envelope_bytes).toHex()` —— 与签名不同，摘要无需密钥，
任何拿到文件的人都能复算。Wave 19b `ExportScreen` 把这个摘要展示给用户
做"亲眼核对"。

### 4. 与 ADR-0005 Recovery Package 的边界

| 维度 | Vault Export Envelope (本 ADR) | Recovery Package (ADR-0005) |
|---|---|---|
| 内容 | 事件流 + blob 清单（明文） | 账户/epoch 密钥的封装材料 |
| 加密 | 不加密，仅签名防篡改 | 必须加密，恢复码分离保管 |
| 谁持有 | 用户主动导出 → 用户自己保管 | 系统生成 → 用户离线保管恢复码 |
| 失窃风险 | 等同于 Vault 解锁状态下的明文 | 失窃 + 数据备份 = Vault 可能被离线解密 |
| 恢复动作 | 用户在新设备上 `importEnvelope` | 用户在新设备上 `restorePackage(recoveryCode)` |
| 版本字段 | `schema_version` | `key_epoch_id`、`algorithm`、`schema_version` |

**禁止**：把 export envelope 当成 recovery package 使用。
**禁止**：在 export envelope 里嵌入任何 Keystore Master Key、Account Epoch Key
或恢复码片段——这违反 ADR-0005 §3 的"恢复包只包含经过保护的密钥恢复材料"
和 ADR-0003 的本地权威边界。

### 5. 版本演进规则

- **新增可选字段**（如 `device_binding_hint`）：`schema_version` 保持 1，
  恢复端必须容忍未知字段（forward-compat）。`VaultExporter.export()` 写出
  的新字段必须同时更新本 ADR 的字段表。
- **修改必填字段的语义或类型**：必须 bump `schema_version` 到 2，并在
  `VaultExporter` 实现一个 `readV1()` + `readV2()` 双解析器。v1 解析器
  至少保留一个 release。
- **删除字段**：禁止。改用 `deprecated_<name>: null` 占位。

### 6. CompositionMode 跨设备恢复的拒绝规则

恢复端（Wave 17c `RecoveryVerifier` 及未来的 `ImportScreen`）必须：

- 读取 `composition_mode` 字段；
- 如果 envelope 是 `prodEncrypted` 而目标设备当前运行 `demo`/`devSqlite`，
  必须弹显式警告："你正把加密 Vault 的导出恢复到非加密设备上。"
  并要求用户输入"CONTINUE" 字面量确认；
- 如果 envelope 是 `demo` 而目标设备是 `prodEncrypted`，
  必须拒绝（不允许"降级污染"）。

## 理由

1. **单文档 JSON 而非 tar.gz**：v1 数据量小（demo 模式事件数通常 < 100），
   单文档能让我们用纯 Dart 单元测试覆盖打包/解析，无需引入 `archive` /
   `tar` 包，也不需要处理流式签名的复杂度。
2. **schema_version 永远写出来**：很多 v1 格式（如早期 SQLite schema）省略
   version 字段，结果演进时只能靠"探测字段名"猜版本——不可审计。本 ADR
   强制 version 永远在文件里，恢复端必须先读 version 再选解析器。
3. **签名密钥默认是 dev seed**：让 widget test 和 CI 可以无 passphrase
   生成、验证 envelope；但**生产 export 必须显式 passphrase**——这一约束
   由 `ExportScreen` UI 强制（passphrase 输入框为空时禁用导出 CTA）。
4. **明文 JSON 而非加密**：与 ADR-0005 "Relay 不得独立解密"的边界一致——
   如果 export envelope 加密，恢复端就需要"密钥分发"机制，那其实就是
   ADR-0005 的 recovery package；两个机制不重叠才能让审计员一眼区分
   "用户主动导出（明文，用户负责）" vs "系统恢复（加密，恢复码分离）"。

## 影响

### 正面
- Wave 17a 的 `VaultExporter` 与 Wave 19b 的 `ExportScreen` 有了合同
 依据，未来增加字段时不会再"拍脑袋"。
- 第三方 reviewer 可以根据本 ADR 验证一份 envelope 是否合规。
- 与 ADR-0005 / ADR-0010 的边界明确，避免设计混淆。

### 负面
- 现有 `VaultExporter.export()` 的字段集合已被冻结为 v1；任何新增必填字段
 必须走 schema_version = 2 的迁移路径，不能"加一个字段就完事"。
- `blob_manifest` 当前始终为空，看起来像是"占位字段"；但这是 Wave 18
 加 InMemoryBlobStore + readAll() 后要填充的关键字段，不能现在删。

### 后续行动
1. [Wave 22+] 当 Keystore-backed signing 落地时，新增 `signing_key_id`
 字段（可选，schema_version 仍 = 1），并在此 ADR 增补 §2.bis 说明
 Keystore key 的选取规则。
2. [Wave 18] 当 `blob_manifest` 真正填充时，必须更新 §1 字段表
 中 `blob_manifest` 的"Wave 17a 始终为 `[]`"说明，改为"v1 规范下
 manifest 元素 schema：`{ref, media_type, byte_length, sha256_hex}`"。
3. [M2-Exit] 写 `tool/validate_export_envelope.py`：给定一份 envelope
 文件，按本 ADR 校验 schema_version、字段完整性、event_count/blob_count
 一致性、HMAC 签名重算。

## 未解决问题

1. **是否需要 `exported_by` 字段**？记录导出动作的 actor id。当前 v1 没写，
 因为 envelope 本身就是明文用户数据，加 actor 字段并不能增加可审计性
 （用户可以任意篡改明文后再签名）。如未来 ADR-0010 evidence ledger
 与 export 联动，可能需要这个字段做交叉引用。
2. **是否需要 `previous_envelope_sha256` 字段**？类似 ADR-0010 的链式结构，
 让多次导出形成一条链。目前不做——export 是用户主动行为，不是必然连续
 的事件流；强行链化会让"用户偶尔导出"变成"必须每次导出都基于上一次"，
 违背直觉。

## 参照

- ADR-0003（本地权威加密混合架构）—— envelope 不加密的边界依据
- ADR-0005（v1 恢复包）—— envelope ≠ recovery package 的边界依据
- ADR-0007（四层加密存储栈）—— envelope 反映哪个 composition_mode 的快照
- ADR-0010（evidence ledger 链）—— SHA-256 + HMAC 模式与本 ADR 的签名
  方案同源，但用途不同
- Wave 17a：`packages/storage_api/lib/src/vault_exporter.dart`
- Wave 19b：`apps/personal_os_app/lib/src/screens/export_screen.dart`
