# 0004 — Android 先行的 Flutter + Dart 架构

日期：2026-08-20  
状态：accepted

## 背景

首位 dogfooding 用户明确希望先把系统放在 Redmi Turbo 手机上，同时要求程序便于跨平台。MVP 的主要采集动作包含拍照、快速记录、任务反馈和离线使用；长期复盘又适合 Windows 大屏。

## 决定

1. Redmi Turbo（Android）作为首个 Primary Vault 和必测真机；
2. Flutter 作为跨平台主客户端；
3. v1 采用纯 Dart 的 domain/application core，并通过 ports 隔离 SQLite、密钥、文件、同步和模型；
4. Windows 随后作为 Secondary Trusted Device；iOS 保持可构建边界但不阻塞首版；
5. Rust 仅在测量证明必要时通过窄接口引入；
6. Tauri 从主客户端候选降为未来 Windows Restricted Collector 的条件候选。

## 理由

- 手机是高频采集和行动反馈入口，先验证真实闭环比同时铺开多端更重要；
- Flutter 覆盖 Android 与桌面，能共享 UI 体系；
- Dart-first 避免 MVP 初期承担 Rust FFI、双语言调试和移动构建复杂度；
- 纯 Dart 核心与平台适配器边界可避免“Flutter 单代码库”演变成不可测试的 UI 内业务逻辑；
- 未来仍保留按证据引入 Rust 或专用桌面采集器的路径。

## 影响

- 原计划的 Flutter/Tauri 对称竞赛改为 Flutter vertical slice 验证；
- Tauri 仅在 Flutter 未通过 Safety Gate 或受限桌面采集器出现独立需求时重启评估；
- M2 不能仅凭架构决策退出，仍需 Android 真机和 Windows 构建/契约证据；
- Redmi/HyperOS 后台限制不能影响数据正确性，前台恢复同步是强制兜底。

## 待验证

- 具体 Redmi Turbo 型号、Android/HyperOS 版本；
- Flutter 下 SQLCipher 与硬件保护密钥的真机组合；
- 进程终止、系统省电限制、照片权限与后台同步行为；
- Windows 上同一核心包和事件 fixture 的确定性。
