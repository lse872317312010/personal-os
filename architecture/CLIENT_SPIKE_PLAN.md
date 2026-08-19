# Flutter / Tauri 垂直 Spike 计划 v0.1

状态：ready to execute；当前运行环境缺少 Flutter/Dart/Rust 工具链

## 目的

用同一个真实纵向切片比较 Flutter 与 Tauri，而不是比较 Hello World、主观 UI 喜好或理论包体。

## 目标平台

- 必测：Windows 11；
- 移动端：用户确认手机平台后选择 Android 或 iOS；
- 可选：另一移动平台只做构建可行性，不进入首轮体验评分。

## 两个 Spike 的共同范围

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

## Flutter Spike

候选 1：Dart core + Flutter UI。  
候选 2：Flutter UI + Rust core，仅在 Dart core 无法满足契约或未来复用收益明确时实施。

必须验证：Windows/移动构建、SQLite/SQLCipher 封装、Keystore/Keychain、后台/恢复同步、照片选择、FFI（若使用 Rust）、错误与取消传播。

## Tauri Spike

Web UI + Rust core，使用严格 capability 配置。必须验证：Windows/移动构建、WebView 数据边界、命令权限、SQLite/SQLCipher、平台密钥、移动后台行为、照片/文件访问和 CSP。

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

两个候选完成必测平台的相同场景，或某候选因明确硬约束失败而提前淘汰。最终决定必须引用评分表和原始测量，不以熟悉度单独决定。

