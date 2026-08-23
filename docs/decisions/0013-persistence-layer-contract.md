# 0013 — 持久化层契约

日期：2026-08-24  
状态：proposed

## 背景

Personal OS 采用本地权威的加密混合架构，并以 Android 为首个平台。
领域和应用代码必须通过稳定 Port 使用存储能力，具体适配器只能在
Composition Root 中组装。

当前仓库已有 in-memory、SQLite schema、Vault driver 等部件，但尚未形成
经过真实设备验证的完整 SQLCipher 生产路径。本 ADR 同时记录：

1. 所有适配器最终必须满足的规范性契约；
2. 当前实现与目标之间的已知差距。

“写入本 ADR”不等于“能力已经实现”。只有契约测试和 evidence 同时通过，
才能把对应能力标记为可用。

## 决定

### 1. 端口与依赖方向

稳定端口位于：

- `packages/storage_api`：`EventStore`、`BlobStore`；
- `packages/security_api`：密钥、解锁和 Vault session 端口。

具体实现位于 `adapters/*`。依赖方向只能是：

`UI / Controller / Application -> Port <- Adapter`

Port 包不得 import adapter 包，也不得识别 adapter 私有异常类型。
Adapter 必须在自身出口把内部失败转换为稳定、结构化且不泄露敏感内容的
端口错误。

`VaultDriver` 当前位于 adapter 包，因此属于实现细节，不是 Application
可直接依赖的稳定 Port。若跨平台实现需要共同生命周期接口，应先把抽象接口
下沉到 security/storage API，再分别实现。

### 2. Composition Root

只有以下位置可 import 具体 adapter：

- `apps/personal_os_app/lib/src/composition/**`；
- 明确列出的 `main.dart`、`main_dev.dart`、`main_prod.dart`。

Widget、Controller、feature、service 和 application use case 只能接收抽象
Port，不能切换运行模式、执行 SQL 或调用平台 Keystore。

该边界由 `tool/check_composition_root.py` 动态发现 adapter 并扫描整个
App `lib/`。新增 adapter 或新增 App 子目录不得要求手工扩充白名单。

### 3. 运行模式与真实性

- `inMemoryDemo`：进程级易失数据，只用于演示和测试；UI 必须持续披露
  “关闭后可能丢失”，不得显示“已加密持久化”。
- `sqliteEncrypted`：只有同时满足真实 SQLCipher、平台不可导出密钥、
  重启恢复、锁定/解锁和失败清理证据后才能暴露给用户。
- 未完成的模式不得通过文件名、枚举名或 UI 文案冒充生产能力。
- Relay 只能持有密文，不得持有完整 Vault 或明文密钥。

### 4. EventStore 契约

`appendAll(events)` 必须满足：

- 空批次是无副作用的成功；
- 整批原子写入，事件、seen-id、projection、outbox 和 sequence 同进同退；
- 按输入顺序 reducer，事件与 outbox sequence 单调；
- 相同 `eventId` 且 canonical 内容相同是幂等 no-op；
- 相同 `eventId` 但 canonical 内容不同必须返回稳定 conflict；
- D4 在任何状态变更前被拒绝；
- 参数错误、锁定和策略拒绝使用稳定端口错误，不暴露 adapter 类型。

`readBySubject`、`readById`、limit 和排序语义必须由共享契约测试定义。
所有适配器必须运行同一组测试，不得把差异列为“out of scope”后仍宣称等价。

### 5. BlobStore 契约

- D4 在读取输入流和创建临时文件前拒绝；
- 写入失败不得留下可寻址 partial blob；
- 内容寻址使用密文摘要或明确不会泄露明文关联性的设计；
- delete 幂等；
- metadata 不包含绝对路径、密钥、设备指纹或可逆敏感值；
- 生产实现必须加密并认证内容，不能仅依赖数据库文件名或 UI 文案。

### 6. Vault 生命周期与并发

解锁、迁移、append、rekey、lock 必须由同一个 Vault-scoped serialized
executor 或等价的显式调度器协调。

“单连接”或“每个操作各自使用事务”不能证明 `rekey` 与 `appendAll`
互斥，因为 Driver 与 EventStore 可能是不同对象和不同事务抽象。

要求：

- 解锁和迁移完成前不暴露业务存储句柄；
- 写操作同时要求 session 与 driver 处于 unlocked；
- unlock 失败关闭连接并释放 key lease；
- rekey 与 append/blob write 互斥；
- rekey 失败不替换 active key；
- lock/close 清除连接、能力租约和内存密钥引用；
- 状态提交与失败清理由显式生命周期标志控制，不依赖 enum 顺序。

### 7. 稳定错误边界

稳定错误必须是 adapter-neutral 的 code + allowlisted safe message。
禁止：

- Port mapper import adapter exception；
- 解析异常 message 正则来决定错误语义；
- 将 `Exception.toString()`、路径、SQL、subject ID、密钥或 stack trace
  放入 UI、日志或 evidence；
- 用 Python 影子异常体系代替真实 Dart 合同测试。

内部 cause 可用于本地受控调试，但不得跨越 adapter 边界或进入 evidence。

## 当前符合度

| 能力 | 当前状态 | 进入生产模式前的门禁 |
| --- | --- | --- |
| in-memory 基础追加 | 部分实现 | 补同 ID 不同内容 conflict |
| SQLite schema/event adapter | 部分实现 | 与 in-memory 共享等价测试 |
| D4 拒绝 | 行为存在但错误类型不统一 | 稳定端口错误 |
| 批次原子性 | 有局部测试 | 跨适配器、projection/outbox 全状态测试 |
| Vault lifecycle | 有 driver 状态机 | 共享 serialized executor 与并发测试 |
| Blob 加密 | 未实现 | 真实 authenticated encryption |
| Android Keystore + SQLCipher | 未设备验证 | 重启、锁定、失败与 rekey evidence |
| 导出/删除/恢复 | 原型或契约阶段 | 端到端实现与真实设备验收 |

因此当前应用只能宣称 synthetic/in-memory MVP，不能宣称生产加密持久化。

## 验证计划

进入 M2 或向用户开放真实数据前必须全部满足：

1. 两个 EventStore adapter 运行同一参数化合同测试；
2. 覆盖同 ID 同内容、同 ID 异内容、D4、负 limit、批中冲突、已存在+
   新批次冲突、projection/outbox/sequence 回滚；
3. 并发测试证明 rekey 与所有写操作不可交错；
4. Android 真机重启后数据仍存在，锁定后无法读取；
5. unlock/rekey 失败后没有连接或 key lease 残留；
6. D4 Blob 拒绝且无临时文件或地址化 partial blob；
7. evidence 绑定候选 commit 和制品 SHA-256，且明确区分 synthetic 与
   device-verified。

## 影响

正面：

- 防止把模拟实现包装成生产能力；
- 保持 Flutter UI、领域逻辑和平台适配器解耦；
- Android 先行，同时保留 Windows/iOS 的同一 Port；
- 多 Agent 可以围绕同一参数化合同并行工作。

成本：

- 需要修复现有 in-memory/SQLite 行为差异；
- 需要引入 Vault-scoped 调度器；
- 导出、删除、恢复必须等待真实加密实现，不能只做可点击 UI。

## 未解决问题

- Blob ciphertext 容器和分块认证格式；
- Android Keystore、Windows DPAPI、iOS Keychain 的能力差异；
- 多 Vault 命名空间；
- 生产备份、恢复与设备撤销的联合协议；
- 稳定错误 code 的 canonical machine-readable 定义。
