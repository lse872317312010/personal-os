# M2 候选方案比较 v0.1

状态：proposal / not frozen

## 1. 数据权威模式

| 方案 | 优点 | 主要问题 | 结论 |
|---|---|---|---|
| Cloud-first | 多设备简单、集中计算 | 违反原始敏感数据本地优先；离线和退出风险高 | Reject |
| 纯单机 local-only | 隐私和实现简单 | 无跨设备补采、同步和灾难恢复 | Reject as final architecture |
| Local-authoritative hybrid | 离线可用；云只做密文中继；可支持受限采集端 | 密钥、冲突、删除传播更复杂 | Recommended |

## 2. 客户端候选

### A. Flutter + Dart core

Flutter 官方支持移动、桌面和 Web，单代码库对首个 MVP 有明显效率优势。优点是迭代快、UI 一致、减少 FFI；缺点是核心契约、加密和平台密钥能力依赖 Dart/插件质量。

适合：先验证 Android/Windows 用户闭环，核心复杂度尚可控。

### B. Flutter UI + Rust core

Flutter 负责跨平台 UI，Rust 实现事件、投影、加密边界和契约测试。优点是核心可复用到 CLI/服务、类型与内存安全强；缺点是 FFI、异步、错误模型、移动构建和调试复杂度明显增加。

适合：M1 核心预计快速复杂化，且确定需要多前端复用时。

### C. Tauri 2 + Web UI + Rust core

Tauri 2 官方覆盖主要桌面和移动平台，并以 WebView + Rust/原生能力组合。桌面体积和 Rust 集成有吸引力；但移动 UX、插件覆盖和跨 WebView 差异需要专项验证。

适合：Windows/桌面优先、Web 技术团队、移动端不是首个关键体验时。

### D. 原生 Android/iOS + 独立桌面

平台体验和密钥/系统能力最好，但早期维护面最大，不适合单用户 MVP 起步，除非首个设备明确只做 Android。

## 3. 本地数据层

### SQLite + 显式事件表/投影表 — Recommended baseline

- 事务成熟；
- WAL 允许读写并行，但同一时间仍只有一个 writer；
- 事件、投影、outbox 和 migration 可放在同一事务边界；
- 必须用 SQLite Backup API 或等价一致性方法，不能只复制 WAL 模式下的 `.db` 文件。

### SQLCipher — Recommended candidate for Vault encryption

提供 SQLite 全库 AES-256 加密和跨平台接口。仍需 OS Keystore/Keychain 保护数据库主密钥，并单独处理 Blob、日志和临时文件。

### CRDT/Automerge — Not primary event store

Automerge 适合 local-first 离线协作和多端同步，但 M1 明确要求高语义冲突不能自动合并。CRDT 可用于未来低风险自由文本或协作视图，不应替代核心事件、Consent、删除和状态机语义。

## 4. 推荐组合（待客户端验证）

- 数据权威：local-authoritative hybrid；
- 本地核心：SQLite 事件表 + 投影表 + outbox；
- 本地加密：SQLCipher 候选 + OS hardware-backed keystore/keychain；
- Blob：独立对象加密，按对象密钥和敏感度管理；
- 同步：客户端生成不可变事件包；云端只存 E2EE 密文和最小路由元数据；
- 冲突：下载并集后由本地 M1 投影器检测和显式解决；
- CRDT：仅限未来低风险子域；
- 客户端：Flutter 与 Tauri 做一个垂直 spike 后决定；若移动优先，Flutter 优先级更高；若 Windows 优先，Tauri 进入强候选。

