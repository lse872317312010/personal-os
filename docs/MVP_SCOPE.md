# MVP 冻结范围

- 版本：v0.2
- 状态：accepted
- 平台：仅Android
- 产品主线：个人资产与目标 → 外部Agent策略 → App监督执行 → 结果反馈 → 策略修订
- 首个领域：外形优化或健身中的一个真实目标，由dogfooding启动时确定

## 要验证的命题

Personal OS能否把个人资产、状态、目标和约束作为长期权威数据，通过MCP交给可替换的外部Agent生成策略与计划，再由Android App监督执行、记录确定性结果和主观反馈，使第二轮Agent策略能够基于第一轮历史完成可解释修订。

## 必须包含

1. Android本地加密保存PersonalAsset、Goal、Constraint和Observation；
2. 明确区分事实、观测、确定性结果、主观反馈、Agent推断、建议和未知项；
3. 建立外部Agent Session，并支持只读/读写两种权限；
4. 通过MCP读取目标相关的资产、历史策略、执行和结果；
5. Agent能够通过MCP维护资产并写入来源；
6. Agent能够创建结构化Strategy及其评价指标；
7. Agent能够创建有限周期Plan和可执行Task；
8. 用户能够接受、修改或拒绝Agent策略和计划；
9. App监督Task完成、跳过、偏离、困难和停止原因；
10. App保存确定性Outcome和SubjectiveFeedback；
11. Agent能够读取第一轮结果，写入Review和Strategy新版本；
12. 展示策略版本变化、修改理由和引用证据；
13. 更换Agent后可以继续同一目标和策略历史；
14. 支持JSON/JSONL无损导出、Context Bundle和Proposal Bundle；
15. 支持Vault锁定、备份、恢复、修订和删除。

## 最小闭环

第一轮：

建立资产和目标 → Agent读取 → Agent写入Strategy v1与Plan → 用户执行 → App记录结果。

第二轮：

Agent读取v1历史 → 写入Review → 创建Strategy v2 → 用户执行 → 对比两轮。

只有完整完成两轮，才能认为MVP核心命题得到初步验证。

## 明确非范围

- Android内置或直接调用特定模型；
- 在App中构造Agent、Prompt或Harness；
- Windows、iOS、Web和桌面客户端；
- 多设备同步和云端Relay；
- 多Agent编排、自动模型选择和渐进披露；
- Graphiti、Mem0、向量数据库或训练个人模型；
- 全自动长期Agent；
- 自动购买、预约、发送消息或公开发布；
- 同时完成全部生活领域；
- 医疗诊断、治疗和高风险不可逆策略；
- 商业化、多用户和团队能力。

## 兼容性要求

内部业务协议不得包含OpenAI、Anthropic、Codex、Claude、Letta等厂商类型。MCP是首选在线接口；JSON/JSONL Bundle是无损兼容和供应商退出接口。

## 变更规则

任何新增功能必须直接支持两轮策略闭环、数据完整性、Agent兼容或Android dogfooding。否则进入MVP之后的backlog。
