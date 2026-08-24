# M2 Verification Matrix

状态：执行中。此矩阵区分“代码/协议存在”与“目标平台证据已取得”，避免用 fake 或桌面 smoke 代替 Redmi Turbo 真机安全结论。

| Gate | 验证对象 | 自动化证据 | 目标平台证据 | 当前状态 |
|---|---|---|---|---|
| M2-G1 | Dart core 确定性与边界 | format、analyze、unit/contract tests | 不需要 | Repository contract 已定义；main 提供相关 Actions workflow，但本审计未取得 main exact commit 的成功 run，证据未绑定候选 commit |
| M2-G2 | Flutter Android shell | analyze、widget tests、APK build | Redmi Turbo 安装、冷启动、离线闭环 | secure composition、observation recording/history UI、controlled Photo Picker 与 Camera wiring 已存在；Camera 拍摄时显式请求权限，并通过 app-private cache/FileProvider、opaque token、native blob sink 及 cleanup/rollback 边界接入；Android workflow 已定义 analyze/test/build 与 Release 步骤，但本审计未取得 main exact commit 的成功 run、APK artifact 或真机证据 |
| M2-G3 | Windows portability | Windows build 与相同 core tests | Windows 启动、Vault open/close | Blocked |
| M2-G4 | SQLCipher Vault | migration、wrong-key、rekey、rollback tests | Android/Windows 加密文件与锁定验证 | native SQLCipher database/event JSON storage 已接入 secure composition；未编译/未运行 integration tests，SQLCipher production verification 未取得 |
| M2-G5 | Device key protection | bridge tests 与错误脱敏 | Keystore capability、认证、撤销、重启 | native Keystore authentication primitive 已实现；未编译/未运行，Android/Redmi 行为未验证 |
| M2-G6 | Encrypted Blob | fake crypto/repository lifecycle tests、bounded ingestion contract | 大文件、进程终止、空间耗尽、crypto-erasure | controlled Photo Picker/Camera→native cache/FileProvider→opaque token→native blob sink→opaque `BlobRef` wiring exists; explicit capture permission and cleanup/rollback paths are implemented; Android compile/runtime, large-file, interruption, crypto-erasure, Redmi, real-model and production evidence 未取得 |
| M2-G7 | E2EE sync | account isolation、AAD、gap、ACK tests | 双设备离线/补采/撤销 | Simulation only |
| M2-G8 | Recovery | 12 fixtures、状态机与非预言机 tests | Android↔Windows 恢复、损坏/旧包演练 | 协议/fixture 级；跨设备演练未完成 |
| M2-G9 | Privacy | D4 multi-layer rejection、secret scan | 日志/备份/系统分享面检查 | Partial |
| M2-G10 | Operability | crash-safe state、诊断错误码 | 升级、降级拒绝、断电与空间耗尽演练 | Not started |

## 2026-08-24 状态证据

- 观测到的 main exact commit：`6d23063c5059174240338a6be11d37949fefbab0`。
- `.github/workflows/flutter-android.yml` 已定义 repository contracts、Dart core、Flutter analyze/test、debug APK 和 rolling Release 流程；这证明 workflow 配置存在，不证明某次构建成功。
- 本次对 main exact commit 的 Actions 查询没有返回成功 run；对 PR #65 head 查询到的 Flutter Android run 状态为 `in_progress`，没有成功结论。
- PR #65 的 GitHub 合并记录显示已合并，但其权限隔离、两阶段 publish job、SHA-256 sidecar 校验内容尚未出现在本次读取到的 main workflow 文件中。该差异需要在下一次 main ref 更新后复核。
- 因此 APK、provenance、rolling Release、SQLCipher production、冷启动恢复、Photo Picker/native blob runtime 和 Redmi dogfood 均保持未验证状态。
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
