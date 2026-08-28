# M2 Verification Matrix

状态：执行中。此矩阵区分“代码/协议存在”与“目标平台证据已取得”，避免用 fake 或桌面 smoke 代替 Redmi Turbo 真机安全结论。

| Gate | 验证对象 | 自动化证据 | 目标平台证据 | 当前状态 |
|---|---|---|---|---|
| M2-G1 | Dart core 确定性与边界 | format、analyze、unit/contract tests | 不需要 | **Automated evidence verified**：main `8eda400471e51a3137ddde3160073db402e2da5d` 的 Repository contracts、Dart core、Dart core (Windows) runs 均成功 |
| M2-G2 | Flutter Android shell | analyze、widget tests、APK build | Redmi Turbo 安装、冷启动、离线闭环 | **Automated build/release verified**：main `8eda400471e51a3137ddde3160073db402e2da5d` 的 Android run 成功，rolling Release 的 APK、SHA-256 sidecar 与 provenance JSON 已发布并校验；Redmi Turbo 安装、冷启动和离线闭环仍未验证 |
| M2-G3 | Windows portability | Windows build 与相同 core tests | Windows 启动、Vault open/close | Blocked |
| M2-G4 | SQLCipher Vault | migration、wrong-key、rekey、rollback tests | Android/Windows 加密文件与锁定验证 | native SQLCipher database/event JSON storage 已接入 secure composition；未编译/未运行 integration tests，SQLCipher production verification 未取得 |
| M2-G5 | Device key protection | bridge tests 与错误脱敏 | Keystore capability、认证、撤销、重启 | native Keystore authentication primitive 已实现；未编译/未运行，Android/Redmi 行为未验证 |
| M2-G6 | Encrypted Blob | fake crypto/repository lifecycle tests、bounded ingestion contract | 大文件、进程终止、空间耗尽、crypto-erasure | controlled Photo Picker/Camera→native cache/FileProvider→opaque token→native blob sink→opaque `BlobRef` wiring exists; explicit capture permission and cleanup/rollback paths are implemented; Android compile/runtime, large-file, interruption, crypto-erasure, Redmi, real-model and production evidence 未取得 |
| M2-G7 | E2EE sync | account isolation、AAD、gap、ACK tests | 双设备离线/补采/撤销 | Simulation only |
| M2-G8 | Recovery | 12 fixtures、状态机与非预言机 tests | Android↔Windows 恢复、损坏/旧包演练 | 协议/fixture 级；跨设备演练未完成 |
| M2-G9 | Privacy | D4 multi-layer rejection、secret scan | 日志/备份/系统分享面检查 | Partial |
| M2-G10 | Operability | crash-safe state、诊断错误码 | 升级、降级拒绝、断电与空间耗尽演练 | Not started |

## 2026-08-28 exact-commit 状态证据

- main exact commit：`8eda400471e51a3137ddde3160073db402e2da5d`（`fix(android): clear P0 build blockers and restore formatter compliance (#70)`）。
- 同一 SHA 的 [Flutter Android APK Release run #33130602184](https://github.com/lse872317312010/personal-os/actions/runs/33130602184) 状态为 `completed/success`。其中 “Verify and package Android debug APK” 与 “Publish rolling GitHub Release” 两个 job 均成功；资产准备、下载后校验及发布步骤均成功。
- 同一 SHA 的 Repository contracts run #33130602211、Dart core run #33130602153 与 Dart core (Windows) run #33130602356 均为 `completed/success`。
- 对应 [android-latest rolling Release](https://github.com/lse872317312010/personal-os/releases/tag/android-latest) 发布于 2026-08-28 00:52:35 UTC，包含：
  - `personal-os-latest-debug.apk`，157,024,141 bytes，GitHub digest `sha256:4ebcc8df0d1285294bda887db6b4dd4a256be713ee61064ca75e15b3616ae580`；
  - `personal-os-latest-debug.apk.sha256`，103 bytes，GitHub digest `sha256:ec15488f529f9d55d7f0297c9464fec7aacf4e1339df7d2dc6e067238372de32`；
  - `personal-os-latest-debug.provenance.json`，308 bytes，GitHub digest `sha256:d7bb387990ada6c0b1e6fe1d279ad315a1caad7afef4f62836504734d7d0034d`。
- 以上证据只验证精确提交的 CI、Android debug APK 构建、资产校验与 rolling Release 发布，不验证 SQLCipher/Keystore 的真实设备行为、冷启动恢复、Photo Picker/Camera/native blob runtime、真实模型或 Redmi dogfood。
- 分支治理证据见 [远程分支与仓库真相审计](BRANCH_AUDIT_2026-08-24.md)。

## Exit rule

M2 只有在下列条件同时满足后才能退出：

1. M2-G1 至 M2-G10 均有可复现证据，且没有 Critical/High 未缓解缺陷；
2. Redmi Turbo 完成离线纵向闭环、锁屏/重启后的 Vault 门禁与至少一次恢复演练；
3. Windows 使用同一事件、策略、同步和恢复 core，通过跨平台 fixture；
4. SQLCipher 与平台密钥保护由真实 adapter 执行，fake 仅作为单元测试证据；
5. 恢复 production crypto suite 经独立安全评审冻结，测试专用 suite 被生产构建拒绝；
6. 所有证据记录工具链版本、设备/系统版本、命令、结果与已知限制。

## Evidence record template

每条证据至少记录：`gate_id`、commit、UTC time、runner/device、OS/toolchain、command/scenario、result、artifact digest、limitations。敏感日志和用户内容不得进入 CI artifact。
