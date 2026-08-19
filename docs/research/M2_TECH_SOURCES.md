# M2 技术调研来源

检索日期：2026-08-20。只记录影响架构判断的官方/项目一手资料。

## 客户端

- [Flutter supported platforms](https://docs.flutter.dev/reference/supported-platforms)：官方覆盖 Android、iOS、Windows、macOS、Linux 和 Web；桌面有正式支持。
- [Flutter multi-platform integration](https://docs.flutter.dev/platform-integration)：单代码库并允许通过插件、platform channels/FFI 接入平台能力。
- [Tauri 2 introduction](https://v2.tauri.app/start/)：官方定位覆盖主要桌面与移动平台，前端使用 HTML/JS/CSS，后端可结合 Rust、Swift、Kotlin。
- [Tauri architecture](https://v2.tauri.app/concept/architecture/)：WebView 与 Rust/原生通过消息边界组合，需把命令权限纳入威胁模型。

## 本地数据

- [SQLite WAL](https://www.sqlite.org/wal.html)：WAL 支持 readers 与 writer 并行，但同一时间只有一个 writer；WAL 依赖同机共享内存，不能直接放网络文件系统；需管理 checkpoint。
- [SQLite Backup API](https://sqlite.org/backup.html)：活动数据库备份应使用一致性 API，而不是随意复制 WAL 模式数据库文件。
- [SQLCipher](https://www.zetetic.net/sqlcipher/)：SQLite 扩展，提供 AES-256 全库加密和跨平台支持；不替代密钥管理与 Blob/日志保护。
- [Android Keystore](https://developer.android.com/privacy-and-security/keystore)：密钥可保持不可导出，并可限制使用条件；适合包装本地 Vault 密钥。

## Local-first 与同步

- [Automerge local-first introduction](https://automerge.org/docs/hello/)：本地副本作为主要数据，支持离线和多设备同步。
- [Automerge repositories](https://automerge.org/docs/reference/repositories/)：提供 CRDT、同步协议以及可插拔 Storage/Network Adapter。
- [Automerge 3](https://automerge.org/blog/automerge-3/)：通过保存变更支持冲突与版本历史，同时也带来历史元数据成本。

## 研究结论

- Flutter 和 Tauri 均具备跨桌面/移动的官方路径，需要用真实垂直 spike 比较插件、移动体验、包体与工程复杂度；
- SQLite 适合作为单设备事务核心，但多设备同步不能靠共享 WAL 文件；
- SQLCipher + OS Keystore 是本地 Vault 的合理候选组合，不是完整安全方案；
- CRDT 与 local-first 理念匹配，但不能覆盖 M1 对 Consent、删除和高语义冲突的显式规则。

