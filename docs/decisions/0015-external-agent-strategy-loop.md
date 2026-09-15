# 0015 — Android权威数据与外部Agent策略闭环

- 状态：accepted
- 日期：2026-09-15
- Supersedes：0002中“最小分析能力”的App内分析解释
- Narrows：0004的跨平台发布范围
- Defers：0003/0005/0012中的多设备、Relay与恢复扩展

## 背景

现有路线把Android内置模型分析、云端Provider边界、Windows客户端和跨设备同步逐渐纳入MVP。进一步澄清后，产品的核心并不是在App中构造模型或Agent，而是长期保存个人资产、目标、策略、执行和结果，并允许Codex或其他可替换Agent利用这些历史生成下一轮策略。

## 决定

1. MVP只发布Android；
2. Android Vault是个人资产和策略历史的唯一权威端；
3. App不直接绑定或运行特定模型；
4. 推理元交互完全由外部Agent/Harness负责；
5. MCP是首选在线接口；
6. Context/Proposal Bundle是兼容和离线接口；
7. Agent可以维护资产、提出Strategy、创建Plan和Review；
8. 所有Agent写入必须经过Application Core；
9. App负责监督Execution并保存Outcome和Feedback；
10. MVP必须完成同一Goal的Strategy v1与v2两轮闭环；
11. 第二种Agent必须能够延续第一种Agent建立的历史；
12. Windows、同步、内置模型、多Agent编排和高级披露延期。

## 理由

- 保持个人数据与策略资产独立于模型厂商；
- 利用不断进化的外部模型，而无需反复改造App；
- 让真实执行结果成为长期资产；
- 避免在产品价值验证前投入过多跨平台和Provider工程；
- 通过MCP与开放Schema获得Harness兼容性；
- 保留现有EventStore、Policy、SQLCipher、Keystore和Blob投资。

## 影响

需要新增或明确：

- PersonalAsset；
- Strategy版本与状态机；
- Execution、Outcome、Feedback和Review关系；
- AgentRef、AgentSession和AgentAudit；
- Agent Gateway API；
- MCP Resources/Tools；
- Context/Proposal Bundle。

需要从MVP组合根解绑：

- OpenAI Responses Android Client；
- Provider credential UI；
- Windows adapters；
- Sync/Relay；
- 模型路由。

## 不代表

- 永久禁止向模型提供完整数据；
- 永久禁止App内模型；
- 放弃多设备和Windows；
- Agent可以绕过用户控制直接修改历史；
- 已经完成MCP或两轮dogfood。

这些能力只能在最小闭环证明价值后重新评估。
