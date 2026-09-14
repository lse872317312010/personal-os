# M2 Verification Matrix

状态：执行中。此矩阵区分“代码/协议存在”“自动化证据已绑定 exact commit”与“目标平台证据已取得”，避免用 fake、Robolectric、桌面 smoke 或 CI 构建代替 Redmi Turbo / Windows 的真实安全结论。

截至 2026-09-14，最近一个完整自动化发布基点为 `85b818ee0b7bd41ff1f190092848b6681915ee2a`。该 commit 的 Repository contracts（run `34838922169`）、Dart core（Ubuntu runner，run `34838922230`）和 Flutter Android APK Release（run `34838922087`）均成功；`android-latest` 也在远端回读 APK/SHA/provenance 后才推进到同一 commit。后续候选仍以 Release provenance 为唯一动态事实源，不以本文静态 SHA 代替。

| Gate | 验证对象 | 自动化证据 | 目标平台证据 | 当前状态 |
|---|---|---|---|---|
| M2-G1 | Dart core 确定性与边界 | format、analyze、unit/contract tests | 不需要 | **自动化已验证**：`85b818ee…` 的 Repository contracts 与 Ubuntu Dart core 均 PASS；这证明平台无关 Dart core，不等同于 Windows 宿主已验证 |
| M2-G2 | Flutter Android shell | analyze、widget/integration tests、Android JVM/Robolectric tests、APK build、provenance/release verification | Redmi Turbo 安装、冷启动、离线/真实 provider 闭环 | **自动化已验证 / 真机待验证**：secure composition、observation history、Photo Picker/Camera、native blob、模型边界、APK 和 rolling Release 均在 `85b818ee…` 通过；Redmi Keystore/SQLCipher 冷启动和真实 provider 仍未取得设备证据 |
| M2-G3 | Windows portability | Windows build 与相同 core/composition tests | Windows 启动、Vault open/close | **进行中**：主分支尚无 `windows/` 宿主；开发分支已先把非 Android production composition 改为 fail-closed，Windows runner/build 与 secure adapter 仍未验证 |
| M2-G4 | SQLCipher Vault | migration、wrong-key、rekey、rollback tests、Android native compile | Android/Windows 加密文件、错误密钥、冷启动与锁定验证 | **自动化部分验证 / 真实 SQLCipher 待验证**：native database/event storage 已接入并成功编译；schema/driver/边界测试通过，但 CI 的 schema audit 明确不把普通 SQLite 测试提升为 SQLCipher production evidence |
| M2-G5 | Device key protection | bridge tests、错误脱敏、Android native compile | Keystore/Windows key protection capability、认证、撤销、重启 | **自动化部分验证 / 设备待验证**：Android Keystore authentication primitive 与 bridge 合约已编译/测试；Redmi 的真实认证、撤销和进程重启生命周期仍未验证 |
| M2-G6 | Encrypted Blob | lifecycle、bounded ingestion、rollback、media boundary tests | 大文件、进程终止、空间耗尽、crypto-erasure、真实模型媒体路径 | **自动化部分验证 / 设备待验证**：Photo Picker/Camera→opaque token→native blob→`BlobRef`、回滚、媒体上界和 HEIF/AVIF 转码边界已进入 Android 自动化；大文件/空间耗尽/进程终止及真实设备 codec 仍待验证 |
| M2-G7 | E2EE sync | account isolation、AAD、gap、ACK tests | 双设备离线/补采/撤销 | **Simulation only**：协议与 worker 测试通过，没有双设备证据 |
| M2-G8 | Recovery | fixtures、状态机与非预言机 tests | Android↔Windows 恢复、损坏/旧包演练 | **协议自动化已验证 / 跨设备待验证**：recovery 状态机与 fixtures 通过，production crypto suite 与跨设备恢复尚未完成 |
| M2-G9 | Privacy | D4 multi-layer rejection、secret-field/contract audits、fail-closed model/source boundaries | 日志、备份、系统分享面与真实设备检查 | **自动化部分验证 / 设备审计待完成**：D4、敏感字段、外部处理 consent、一次性凭据和错误脱敏已有自动化；系统级泄漏面仍需真机检查 |
| M2-G10 | Operability | crash-safe/state-machine tests、稳定错误码、release provenance | 升级、降级拒绝、断电、空间耗尽与恢复演练 | **自动化部分验证 / 故障演练待完成**：事务、回滚、稳定错误码和 exact-commit APK 交付已验证；断电/空间耗尽/升级降级仍无目标平台证据 |

## Exit rule

M2 只有在下列条件同时满足后才能退出：

1. M2-G1 至 M2-G10 均有可复现证据，且没有 Critical/High 未缓解缺陷；
2. Redmi Turbo 完成离线纵向闭环、锁屏/重启后的 Vault 门禁与至少一次恢复演练；
3. Windows 使用同一事件、策略、同步和恢复 core，通过跨平台 fixture，并具备真实 secure adapter 的 Vault open/close 证据；
4. SQLCipher 与平台密钥保护由真实 adapter 执行，fake/Robolectric 仅作为自动化辅助证据；
5. 恢复 production crypto suite 经独立安全评审冻结，测试专用 suite 被生产构建拒绝；
6. 所有证据记录工具链版本、设备/系统版本、命令、结果与已知限制。

## Evidence record template

每条证据至少记录：`gate_id`、commit、UTC time、runner/device、OS/toolchain、command/scenario、result、artifact digest、limitations。敏感日志和用户内容不得进入 CI artifact。
