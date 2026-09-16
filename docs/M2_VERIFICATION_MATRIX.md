# M2/M3验证矩阵

状态：方向重构后重新基线。

旧矩阵中的Windows、跨设备同步和Android内置模型不再是MVP退出条件。既有自动化证据仍证明相关代码基线，但不能替代新方向的Agent Gateway与两轮策略闭环验证。

| Gate | 验证对象 | 自动化证据 | 真实证据 | 当前状态 |
|---|---|---|---|---|
| G1 | Core确定性与边界 | Dart unit/contract tests | 不需要 | 现有基线可复用，需新增Strategy/Agent事件 |
| G2 | Android Vault | Flutter/Android tests、APK | Redmi解锁、冷启动、杀进程、恢复 | 部分完成，真机待重验 |
| G3 | PersonalAsset与Goal | Domain/Application tests | 建立一个真实目标上下文 | 待扩展 |
| G4 | Strategy生命周期 | 状态机与事件fixtures | v1/v2真实策略 | 待实现 |
| G5 | Execution与Outcome | 命令、投影和不可篡改测试 | 一个有限周期执行记录 | 基础Task存在，证据关系待扩展 |
| G6 | MCP Gateway | Protocol/adapter tests | Codex真实读写Session | 未实现 |
| G7 | Agent可替换性 | Schema compatibility tests | 第二Agent延续第一Agent历史 | 未实现 |
| G8 | Bundle兼容 | JSON/JSONL round-trip | 离线Context/Proposal往返 | 未实现 |
| G9 | 安全与审计 | D4、Session、错误脱敏测试 | Session关闭后访问失败 | 部分基础可复用 |
| G10 | 两轮策略闭环 | journey tests | 同一Goal完成v1→Review→v2 | 未执行 |
| G11 | 导出与恢复 | round-trip tests | Redmi清空/恢复后历史一致 | 部分协议存在，待新Schema验证 |

## MVP退出规则

必须同时满足：

1. G1至G11通过；
2. Android是唯一权威端，Agent不可用不影响数据维护；
3. Codex或一种真实Agent通过MCP完成读写；
4. 第二种Agent不修改核心Schema即可延续历史；
5. 同一Goal完成两轮真实Strategy执行；
6. Strategy v2引用第一轮Execution、Outcome或Feedback；
7. 数据可无损导出和恢复；
8. 没有Critical/High未缓解缺陷。

## 旧证据处理

最近完整Android自动化发布基点85b818ee0b7bd41ff1f190092848b6681915ee2a仍可证明：

- 既有Dart/Flutter/Android构建基线；
- SQLCipher、Keystore、Blob和UI代码能够集成；
- APK、SHA-256和provenance链能够工作。

它不能证明：

- 新Strategy/Agent领域模型；
- MCP Gateway；
- Agent可替换性；
- 两轮真实策略闭环。

## 证据模板

每条证据记录：

- gate_id；
- exact commit；
- UTC time；
- runner/device；
- OS/toolchain；
- command/scenario；
- agent/harness及版本；
- result；
- artifact digest；
- limitations。

不得把synthetic输出或Agent自我评价作为真实效果证据。
