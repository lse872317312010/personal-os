# M2 Verification Matrix

状态：执行中。此矩阵区分“代码/协议存在”与“目标平台证据已取得”，避免用 fake 或桌面 smoke 代替 Redmi Turbo 真机安全结论。

| Gate | 验证对象 | 自动化证据 | 目标平台证据 | 当前状态 |
|---|---|---|---|---|
| M2-G1 | Dart core 确定性与边界 | format、analyze、unit/contract tests | 不需要 | Blocked：环境无 Dart SDK |
| M2-G2 | Flutter Android shell | analyze、widget tests、APK build | Redmi Turbo 安装、冷启动、离线闭环 | Blocked |
| M2-G3 | Windows portability | Windows build 与相同 core tests | Windows 启动、Vault open/close | Blocked |
| M2-G4 | SQLCipher Vault | migration、wrong-key、rekey、rollback tests | Android/Windows 加密文件与锁定验证 | Contract only |
| M2-G5 | Device key protection | bridge tests 与错误脱敏 | Keystore capability、认证、撤销、重启 | Contract only |
| M2-G6 | Encrypted Blob | fake crypto/repository lifecycle tests | 大文件、进程终止、空间耗尽、crypto-erasure | Core implemented |
| M2-G7 | E2EE sync | account isolation、AAD、gap、ACK tests | 双设备离线/补采/撤销 | Simulation only |
| M2-G8 | Recovery | 12 fixtures、状态机与非预言机 tests | Android↔Windows 恢复、损坏/旧包演练 | Protocol complete |
| M2-G9 | Privacy | D4 multi-layer rejection、secret scan | 日志/备份/系统分享面检查 | Partial |
| M2-G10 | Operability | crash-safe state、诊断错误码 | 升级、降级拒绝、断电与空间耗尽演练 | Not started |

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
