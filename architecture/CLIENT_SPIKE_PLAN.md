# Flutter 垂直 Spike 计划 v0.2

状态：ready to execute；当前运行环境缺少 Flutter/Dart/Rust 工具链

## 目的

验证已选的 Flutter + Dart-first 路径是否能在真实手机和 Windows 上满足 M1 契约、安全门槛与跨平台维护目标，而不是比较 Hello World 或主观 UI 喜好。

## 目标平台

- 必测 1：Redmi Turbo / Android（Primary Vault）；
- 必测 2：Windows 11（Secondary Trusted Device）；
- 后续：iOS 只验证构建与关键适配器可行性，不阻塞首轮闭环。

## Vertical slice 范围

1. 打开本地 Vault；
2. 创建 Goal、Observation、Claim、Plan 和 Task；
3. 在单一事务中追加 event、更新 projection、写入 outbox；
4. 展示当前状态与完整来源链；
5. 完成/跳过 Task 并创建 Review；
6. 撤销 Consent，使新的 D3 Observation 被拒绝；
7. 模拟第二设备并发修改，显示显式 conflict；
8. 执行 L2 删除并验证 Snapshot 不含原内容；
9. 导出一份可读的事件/对象包；
10. 离线重启后确定性重建。

## 共同数据与测试

- 使用 `specs/EVENT_SEQUENCES.md` 的 S1–S4 固定 fixture；
- 使用 `specs/CONTRACT_TESTS.md` 的 CT-001、002、003、105、203、301、303、402、501–504；
- 使用相同对象数量、事件数量、Blob 大小和加密配置；
- 禁止某个候选绕过 Rust/FFI、数据库加密或平台密钥难点来获得虚假优势。

## 实现路径

基线为 Dart core + Flutter UI。Flutter app 只能通过 application 层访问业务能力；数据库、密钥、文件和同步使用可替换 adapter。

必须验证：Windows/移动构建、SQLite/SQLCipher 封装、Keystore/Keychain、后台/恢复同步、照片选择、FFI（若使用 Rust）、错误与取消传播。

## 条件分支

- 只有 Dart core 在契约、性能或安全上有测量失败，才评估 Rust 窄接口；
- 只有 Flutter 未通过 Safety Gate，或 Windows Restricted Collector 出现独立需求，才执行 Tauri spike；
- 任何条件分支都必须记录失败证据，不能因技术偏好触发。

## 采集指标

- clean build 与增量 build 时间；
- release 包体和冷启动时间；
- S1 完整提交与 10k 事件重放耗时；
- 峰值内存、数据库增长与 Snapshot 大小；
- 平台特有代码行数；
- 跨层 API/FFI 数量；
- 契约测试通过率；
- D3 明文临时文件与日志检查；
- 调试、错误定位和自动化测试体验。

## 退出条件

Flutter 在 Android 真机和 Windows 完成同一场景，Safety Gates 全部通过，原始测量与复现命令进入仓库。若失败，按条件分支重新打开候选比较。
