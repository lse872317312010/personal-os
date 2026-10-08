# 发展路线与里程碑

## 当前产品方向

更新日期：2026-10-08（Asia/Shanghai）。

Personal OS 保存结构化个人资料和连续行动历史，用户选择的 GPT 或其他
Agent 提供计划与复盘。**当前只推进本机 Web 自动 Agent 闭环**，Android
保留为后续设备方向。Windows/Linux 启动包维护、Android 真机、同步和多
Agent 编排后排，依据决策 0019。

当前是功能原型验证阶段：自动计划、确认、明确反馈、复盘、下一轮及刷新恢复
已由模型替身验证；真实账号推理、真实两轮使用和跨服务接续未完成。
最新本地验证为 Flutter 全量 146 项通过、静态检查无问题、Web release
构建成功。当前改动整理为 Web 候选提交，新增恢复测试纳入 Chrome CI，
最新浏览器执行证据仍待本轮 CI；候选版本尚未合并或发布。
详细验证边界见 [WEB_STATUS.md](WEB_STATUS.md)。

## 当前执行计划

阶段以完成判据推进，不按测试数量或新增功能数量宣布完成。

| 顺序 | 交付目标 | 工作范围 | 完成判据 |
| --- | --- | --- | --- |
| W0：优先 | 固定一个可复现的 Web 候选版本 | 整理当前改动并提交；补齐新启动脚本的 CI 触发范围、多行动冷启动的 Chrome 覆盖；在可启动浏览器的环境验证手机/桌面编译页面 | 同一提交的核心/应用/网关检查通过，最新 Chrome 与编译页面截图齐备，编译产物可对应到提交；推送、CI 和发布分别记录，不能用本地结果代替 |
| W1：优先 | 一种真实 Agent 自动接入成功 | 验证当前账号实际可用的 ChatGPT 授权或用户选择的 API/HTTP Agent；检查模型目录、连接测试及正式计划请求；修复真实鉴权、响应格式和错误恢复阻塞 | 用户在应用完成连接，收到真实模型生成且通过协议校验的计划；全程无需手动搬运提示词/回复，日志不保存凭据 |
| W2：优先 | 同一目标完成两轮真实闭环 | 用户明确确认计划并反馈实际完成或跳过；Agent 复盘后生成 v2；刷新及网关重启恢复；根据这段实际流程修复问题 | v2 沿用同一目标，明确引用第一轮结果；原始事实不被改写，无重复执行/结果，历史和当前行动恢复一致；保存两轮验收记录 |
| W3：接续 | 让历史价值可见，并验证换 Agent | 在行动卡附近提供简短的“这轮改了什么、依据哪次反馈”；历史详细证据按需展开；接入第二种真实服务继续同一目标 | 用户能直接看懂 v1→v2 的主要变化与证据；第二个服务无需重填资料或导入历史即可生成后续复盘/计划 |
| W4：日常试用前 | Web 数据能退出和恢复 | 梳理 Web 网关独立历史的用户备份/恢复路径；不把 Android `.posb` 能力当作 Web 已具备；连接凭据与用户历史分开处理 | 用户可从 Web 入口导出并恢复历史，在空白本机环境验证目标、行动、结果和版本链一致；异常导入不破坏原数据，凭据不混入普通历史导出 |

W0 可以立即推进。W1 的首次登录/授权和服务选择需要用户在应用完成；这不
阻塞候选版本整理、最新浏览器验证或 W3 的变化展示设计。W2 的行动与反馈必须
来自用户，测试记录不能代替。W3 可提前实现展示，但完成跨 Agent 验收需要
两种实际可用服务。

每轮迭代固定处理一项真实使用阻塞或一项上述交付目标，验证后记入阶段记录。
不继续无限扩充模拟用例；发现具体数据完整性或恢复缺陷时仍及时补回归。

## 当前试用验收与长期验收

- W0–W3 完成，才可称为“Web 真实两轮闭环和跨 Agent 接续已验收”；
- W4 完成后再扩大到持续日常试用，之后用 2–6 周记录判断复盘是否有实际价值；
- 两轮功能验收不等于长期效果验证，也不代表 Android 的 G3/G4 或
  `DOGFOOD_READY` 已通过；
- 当前不引入云端个人数据托管，不承诺公开 GitHub Pages 已能独立运行应用。
  当前应用仍由浏览器与本机网关共同运行。

## 长期里程碑记录

以下 M0–M6 保留既有 Android 设备与生产就绪标准。它们不是当前 Web 工作的
执行顺序；Android 在线 MCP、Redmi 真机和同步等待后续恢复。

## M0：产品与领域契约 — Completed

- Android-only MVP、Redmi Primary Vault；
- 外部 Agent 推理与 Android 权威边界；
- 事实、观测、结果、反馈、推断和建议分离；
- D0–D4 数据分类与 R0–R4 风险边界；
- Windows、同步、Relay、内置模型和多 Agent 编排延期。

## M1：Core Data Model & Event Log — Completed

- PersonalAsset、Goal、Strategy、Execution、Outcome、Review、AgentSession；
- append-only 事件、revision、谱系、确定性投影；
- Strategy proposed/accepted/active 生命周期；
- Agent 提案与用户执行/结果权限分离；
- 旧事件兼容和 SQLite schema v2 migration。

## M2：Android 权威 Vault — Build verified，device verification pending

已完成：

- [x] Flutter Android Shell 与 Dart-first core；
- [x] Android Keystore + native SQLCipher；
- [x] Encrypted Blob、Photo Picker 与 Camera；
- [x] EventStore 完整分页与冷启动投影恢复；
- [x] 口令加密 `.posb` 备份、认证导入、原子恢复与强制重锁；
- [x] APK SHA-256、provenance 与 rolling Release；
- [x] G3 九场景的唯一规范、schema v2 与验证器。

剩余：

- [ ] 在同一已验证 APK 上完成 Redmi 九场景；
- [ ] 保存去敏的 real-device v2 证据；
- [ ] 不以 CI、模拟器或 synthetic record 替代真机结论。

## M3：Agent Gateway — Protocol complete，live transport pending

已完成：

- [x] 厂商无关 Agent Protocol v0；
- [x] 固定 revision 的 Context Bundle；
- [x] Proposal Bundle 与 Review Bundle；
- [x] read/write Session、Harness 身份绑定与关闭失效；
- [x] Application Command 权限边界；
- [x] 第二 Harness 接续同一历史的契约测试；
- [x] Android 离线复制/导入兼容路径；
- [x] MCP 2025-06-18 JSON-RPC握手、工具发现、调用适配和稳定错误；
- [x] 每次调用重验Session生命周期、Harness身份和授予的capability。

剩余：

- [x] 冻结 Android 前台临时 MCP 传输威胁模型；
- [ ] 仅在 Vault 解锁且用户显式启动时开放；
- [ ] 短期凭证、loopback/ADB 或受控局域网绑定；
- [ ] 锁定、退后台、超时和 Session 关闭时立即终止；
- [ ] 用真实外部 Harness 完成在线连接，不能放宽离线路径的同一校验。

## M4：两轮真实策略 Dogfooding — Not run

同一 Goal、同一候选版本、2–6 周内完成：

第一轮：

- Strategy v1 与有限期 Plan；
- 用户确认、真实 Execution、Outcome 和 Feedback；
- Agent Review 明确引用第一轮证据。

第二轮：

- 不同 Harness 接续完整历史；
- Strategy v2 以 v1 为 parent；
- v2 明确使用 v1 证据并因反馈产生可解释变化；
- 完成第二轮执行、结果和两轮比较。

退出条件：

- G0–G4 schema v2 审计输出 `DOGFOOD_READY`；
- 用户确认连续策略或复盘价值高于一次性对话；
- 无 Critical/High 未缓解的数据完整性或安全缺陷。

## M5：策略资产增强 — Deferred until M4 passes

- 策略效果统计与相似条件检索；
- 跨领域策略迁移；
- 可重建时态索引；
- 多 Agent 候选比较与细粒度授权；
- 数据连接器和传感器输入。

## M6：多设备与平台化 — Deferred

- Windows Secondary Trusted Device；
- Android↔Windows E2EE；
- Encrypted Relay 与 Restricted Collector；
- iOS/Web、多用户和商业化。

## 长期阶段中仍延期的事项

- Android 内置 OpenAI/其他模型 SDK；
- Android 内置模型接入与选择；Web 已通过本机网关支持服务与模型配置；
- Windows 生产开发；
- 多设备同步与 Relay；
- 多 Agent 编排和自动策略选择；
- 高级渐进披露、向量数据库和个人模型训练。

旧决策 0016 的执行顺序已由 0017–0019 及本页当前计划更新。手动回复导入只
保留为兼容路径，不是 Web 日常操作主线；下一步不推进 APK 或桌面启动包。
