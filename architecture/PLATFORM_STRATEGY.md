# M2 平台策略 v0.1

状态：accepted

## 已冻结结论

- 首个 Primary Vault：用户的 Redmi Turbo（Android）；
- 主客户端：Flutter，Android 先行，并保持 Windows、iOS、macOS 和 Linux 的可移植边界；
- v1 核心运行时：纯 Dart domain/application packages，不依赖 Flutter UI；
- Windows 家用设备：后续作为 Secondary Trusted Device，承担大屏复盘、批量整理与导出；
- 公司电脑：仅可作为 Restricted Collector，不保存完整 Vault 或可浏览的 D2/D3 投影；
- Tauri 不作为主客户端；未来只有在 Windows 受限采集器有明确收益时才单独评估；
- Rust 不进入 v1 默认路径；只有测量证明密码学、同步性能或多前端复用确有需要时，才经稳定接口引入。

## 手机优先交互

Android 首个纵向闭环必须适合单手、碎片时间和弱网：

1. 本地解锁 Vault；
2. 拍照或选择照片，记录外貌 Observation；
3. 查看带来源与不确定性的 Claim；
4. 接受、修改或拒绝低风险 Plan；
5. 快速完成/跳过 Task 并记录原因；
6. 创建 Review，看到前后变化；
7. 离线完成上述流程，联网后再同步密文事件。

桌面端不复制手机界面，而是共享同一核心能力，提供时间线、证据对照、批量编辑、冲突处理、导入导出与长期复盘。

## 跨平台硬边界

- `domain`、`events`、`policy`、`application` 不得 import Flutter 或平台插件；
- UI 只调用 application commands/queries，不直接读写 SQLite；
- 数据库、密钥库、文件、相机、后台任务和同步均通过 ports 注入；
- 平台差异封装在 adapters，事件格式和业务规则不随平台分叉；
- 核心契约测试在无 UI、无网络、无 Android runtime 的环境中运行；
- 跨平台不等于所有平台同时发布：Android 先验证闭环，随后复用核心到 Windows，再验证 iOS 构建。

## 首轮发布顺序

| 顺序 | 目标 | 退出证据 |
|---:|---|---|
| 1 | Android / Redmi Turbo 开发构建 | 安装、解锁、本地闭环、离线重启、加密存储通过 |
| 2 | Windows Secondary Trusted Device | 同一事件 fixture 重放一致；选择性同步与冲突可见 |
| 3 | Android ↔ Windows E2EE 同步 | 中继无明文；撤销设备后不能读取新事件 |
| 4 | iOS 构建可行性 | 核心包与 UI 可编译，Keychain/后台约束有适配方案 |

## Redmi 真机专项

首轮验证需记录具体 Android/HyperOS 版本，并测试：后台限制、电池优化、照片权限、锁屏后密钥行为、进程被杀后的事务恢复、离线队列和通知权限。任何依赖后台常驻的设计都不作为正确性的前提；恢复同步必须可由前台启动兜底。
