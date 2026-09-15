# Windows Secondary Trusted Device secure adapter

状态：implementation contract；尚未达到 production-ready

本文件冻结 M2 Windows Secondary Trusted Device 的原生安全边界。它定义可以开始实现的最小方案，但**不**表示 Windows 已经取得 Vault、TPM、SQLCipher 或跨设备验收证据。`AppComposition.forTargetPlatform(TargetPlatform.windows)` 在这些 gate 完成前必须继续 fail-closed。

## 1. 平台基线

- Trusted Device 最低系统：**Windows 11 / build 22000**。
- Flutter/Dart 与 native 之间的私有通道固定为 `personal_os/internal/windows_vault`。
- Dart 侧复用 `MethodChannelPlatformSecurityBridge` 的同一 wire contract、稳定错误码和脱敏规则；Windows 不复制一套业务协议。
- Windows 10 不通过降低认证要求进入 Trusted Device 路径。若未来需要支持，只能作为单独 capability/profile 重新评审。

选择 Windows build 22000 的直接原因是 Win32 `IUserConsentVerifierInterop::RequestVerificationForWindowAsync(HWND, ...)` 的 Microsoft 文档把 Minimum supported client 标为 Windows Build 22000。该 API 将认证 UI 绑定到当前应用窗口，并可使用 Windows Hello、Microsoft Passport PIN 或指纹等设备能力。

## 2. 信任边界

Flutter/Dart 永远只能看到：

- capability flags；
- opaque authentication ticket ID + expiry；
- opaque vault session ID；
- opaque key reference（ID / purpose / version）；
- wrapped-key ciphertext；
- allowlisted stable error code。

以下内容不得跨 MethodChannel：

- PIN、Windows Hello/biometric material；
- CNG private key material；
- Vault Master Key plaintext；
- SQLCipher key bytes；
- TPM/KSP internal handles；
- filesystem path、key alias、native exception message/details；
- unbounded diagnostic data。

原生敏感缓冲区在最短生命周期内持有，并在 finally/RAII cleanup 中显式 `SecureZeroMemory`；CNG handle 使用 `NCryptFreeObject` 释放。不得生成明文临时文件。

## 3. W1 — user-presence + capability probe

第一阶段只实现安全探测与认证，不开放 Vault。

### `inspectCapabilities`

必须实际探测而不是根据机型/OS 猜测：

1. OS build >= 22000；
2. Win32 UserConsentVerifier interop 可用；
3. `NCryptOpenStorageProvider(..., MS_PLATFORM_CRYPTO_PROVIDER, 0)` 成功；
4. provider/key capability 能证明 hardware-backed / TPM 路径；
5. non-exportable key 能按本文件 W2 的 policy 创建/验证后，才能报告 `nonExportableKeys=true`。

初始 `atomicDeviceRevocation=false`。不能因为存在 TPM 设备或 provider 名称就自动升级尚未验证的高阶 capability。

### `authenticate`

使用 `IUserConsentVerifierInterop::RequestVerificationForWindowAsync`，传入当前 Flutter runner 的 HWND。只有 `UserConsentVerificationResult::Verified` 才可签发 native authentication ticket。

Ticket 要求：

- 使用不可预测的 opaque ID；
- 只存 native process memory；
- 绑定当前进程/用户会话；
- 有短 TTL；
- 到期、锁定、进程退出时失效；
- Dart 只收到 ID 和 expiry，不收到认证类型或 biometric/PIN 数据；
- 取消、拒绝、不可用、过期分别映射到现有 allowlisted security codes；未知 HRESULT/WinRT 错误统一映射 unavailable，原始文本不得出边界。

W1 完成后，`openVault/createKey/wrapKey/...` 仍可以 fail-closed；不得因此把 Windows 接入 production composition。

## 4. W2 — TPM-backed Device Wrapping Key

长期 Device Wrapping Key 使用 Windows CNG Key Storage API，而不是应用自己保存私钥。

### Provider

打开：

`NCryptOpenStorageProvider(&provider, MS_PLATFORM_CRYPTO_PROVIDER, 0)`

Microsoft Platform Crypto Provider 是 Windows 内置 TPM Key Storage Provider。若 provider 不可用，Trusted Device capability fail-closed，不回退到软件私钥后仍声称 `tpm` 或 `nonExportableKeys`。

### Persisted wrapping key

建议 v1 使用 TPM-backed persisted RSA key：

1. `NCryptCreatePersistedKey` 创建 key object；
2. 在 `NCryptFinalizeKey` 之前设置必要属性；
3. `NCRYPT_EXPORT_POLICY_PROPERTY` 显式设为 `0`，不启用 `NCRYPT_ALLOW_EXPORT_FLAG`、`NCRYPT_ALLOW_PLAINTEXT_EXPORT_FLAG`、archiving flags；
4. finalize 后重新读取关键属性/capability，验证不允许 private-key export；
5. key reference 暴露给 Dart 时只提供随机/稳定 opaque ID、purpose、version。

不得提供“导出 private key”调试后门。

### Vault Master Key wrapping

- Vault Master Key (VMK) 使用系统 CSPRNG 产生，原始 bytes 只存在 native memory。
- 用 TPM-backed RSA wrapping key + `NCryptEncrypt`/`NCryptDecrypt`。
- padding 固定为 `NCRYPT_PAD_OAEP_FLAG` + `BCRYPT_OAEP_PADDING_INFO`，hash 固定 SHA-256；禁止 no-padding/自定义 RSA padding。
- wrapped VMK ciphertext 可以持久化；TPM private key 与 VMK plaintext 不可持久化到普通文件、日志或 MethodChannel。
- 解封只允许在最近一次有效 user-presence ticket 后执行。
- VMK 在 native SQLCipher keying 完成后尽快 zeroize。

## 5. W3 — native SQLCipher Vault

只有 W1/W2 通过后才实现 Windows Vault：

1. user presence -> native authentication ticket；
2. ticket 验证 -> TPM unwrap VMK；
3. native 层使用 VMK 打开/验证 SQLCipher；
4. 返回 opaque `PlatformVaultSession`；
5. Dart event/storage adapter 只通过 session capability 操作，不接触数据库 key/path；
6. lock、session expiry、process teardown 时关闭 DB、清理 session/ticket/temporary VMK material。

Windows SQLCipher schema/事件 codec 必须与 Android 使用相同 core contract；平台不得创建另一套事件模型。

## 6. DPAPI 使用规则

DPAPI 不是 Windows Trusted Device 的 user-presence 机制。

允许：未来用于少量、静态、非核心 key material 的 per-user/per-machine at-rest protection，且经过单独威胁评审。

禁止：

- 用 `CRYPTPROTECT_PROMPTSTRUCT` 提示当作 Vault 认证；
- 以 DPAPI 成功替代 Windows Hello/UserConsentVerifier proof；
- 使用 `CRYPTPROTECT_LOCAL_MACHINE` 保护可解锁完整 Vault 的秘密；
- 把 DPAPI 产物解释成 TPM/non-exportable-key 证据。

Microsoft 已将 CryptProtectData/CryptUnprotectData 的 PromptStruct interactive flow 标记为 deprecated，并说明将在 2027 年 2 月移除，因此新设计不得依赖它。

## 7. Production composition gate

在以下证据全部具备前，production `AppComposition` **不得**实例化 `WindowsPlatformSecurityBridge`：

1. Windows 11 build >= 22000 真机/runner build evidence；
2. UserConsentVerifier success/cancel/deny/unavailable 测试；
3. TPM provider probe 与 software-provider rejection；
4. non-exportable wrapping-key policy 验证；
5. RSA-OAEP-SHA256 wrap/unwrap round-trip + malformed ciphertext rejection；
6. ticket expiry/replay/process-restart rejection；
7. VMK/temporary buffer zeroization review；
8. native SQLCipher wrong-key、cold-open、lock/reopen、corruption/rollback tests；
9. no plaintext secret/path/native details through MethodChannel/logs；
10. Windows build + same Dart/core fixtures；
11. Android regression suite remains green。

在 gate 之前，Windows UI 可以启动，但 Vault 必须保持 `security.unlock_unavailable` fail-closed shell。

## 8. M2 evidence boundary

Windows portability workflow 通过，仅可证明 shell/build portability。W1 通过才证明 user-presence/capability adapter；W2 通过才证明 TPM key boundary；W3 通过才证明 Windows local encrypted Vault。只有 W1-W3 和 M2 Verification Matrix 的跨平台 fixture/恢复条件同时满足，Windows 才能升级为 Secondary Trusted Device。

## 9. Microsoft primary references

- `IUserConsentVerifierInterop::RequestVerificationForWindowAsync`: https://learn.microsoft.com/en-us/windows/win32/api/userconsentverifierinterop/nf-userconsentverifierinterop-iuserconsentverifierinterop-requestverificationforwindowasync
- `NCryptOpenStorageProvider`: https://learn.microsoft.com/en-us/windows/win32/api/ncrypt/nf-ncrypt-ncryptopenstorageprovider
- CNG Key Storage Providers / Microsoft Platform Crypto Provider: https://learn.microsoft.com/en-us/windows/win32/seccertenroll/cng-key-storage-providers
- `NCryptCreatePersistedKey`: https://learn.microsoft.com/en-us/windows/win32/api/ncrypt/nf-ncrypt-ncryptcreatepersistedkey
- Key Storage Property Identifiers (`NCRYPT_EXPORT_POLICY_PROPERTY`): https://learn.microsoft.com/en-us/windows/win32/seccng/key-storage-property-identifiers
- `NCryptEncrypt`: https://learn.microsoft.com/en-us/windows/win32/api/ncrypt/nf-ncrypt-ncryptencrypt
- `BCRYPT_OAEP_PADDING_INFO`: https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/ns-bcrypt-bcrypt_oaep_padding_info
- CNG portal / API selection: https://learn.microsoft.com/en-us/windows/win32/seccng/cng-portal
- `CryptProtectData`: https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata
