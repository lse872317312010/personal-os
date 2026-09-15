# MVP 验收标准

状态：Android Agent-driven MVP accepted

## A. 数据与信息质量

- AC-001：每个核心对象具有稳定ID、Schema版本、来源和时间；
- AC-002：UserFact、Observation、DeterministicOutcome、SubjectiveFeedback、AgentInference、Recommendation和Unknown可区分；
- AC-003：修订创建新版本或事件，不覆盖历史；
- AC-004：AgentInference不得显示为用户确认事实；
- AC-005：Strategy、Execution、Outcome和Review引用完整；
- AC-006：同一事件序列能够确定性重建相同状态。

## B. Agent兼容接口

- AC-101：外部Agent可通过MCP列出活动目标并读取目标上下文；
- AC-102：读写Agent可维护资产、创建Strategy、Plan和Review；
- AC-103：所有Agent写入通过Application Commands；
- AC-104：只读Session的写请求失败关闭；
- AC-105：Session关闭、锁屏或失效后不能继续访问；
- AC-106：MCP返回稳定结构化错误，不泄露密钥、数据库路径或原始异常；
- AC-107：核心Schema不包含特定模型或厂商类型；
- AC-108：第二个Agent可继续第一个Agent建立的策略历史；
- AC-109：Context Bundle与Proposal Bundle可完成等价的离线交换。

## C. 策略与计划

- AC-201：Strategy引用Goal并包含假设、适用条件、预期结果和评价指标；
- AC-202：Agent创建的Strategy初始状态为Proposed；
- AC-203：用户可接受、修改或拒绝；
- AC-204：Plan有明确起止时间；
- AC-205：Task具有完成条件、频率/截止和停止条件；
- AC-206：Strategy v2引用v1并展示差异与理由；
- AC-207：没有Execution/Outcome证据时，策略不能标记为已验证有效。

## D. 执行与反馈

- AC-301：用户可记录完成、跳过、偏离和原因；
- AC-302：历史Execution不得原地修改；
- AC-303：确定性Outcome与主观Feedback分别保存；
- AC-304：App能够展示今日任务和周期进度；
- AC-305：周期结束进入Review due，不静默无限续期；
- AC-306：Review分别引用Strategy、Execution、Outcome和Feedback；
- AC-307：Review结论区分Effective、Ineffective、Inconclusive和ExecutionInsufficient。

## E. Android与存储

- AC-401：Redmi真机可安装、解锁和关闭Vault；
- AC-402：核心记录在离线状态可创建和读取；
- AC-403：杀进程和重启后状态正确恢复；
- AC-404：结构化数据由SQLCipher保存；
- AC-405：附件由Encrypted Blob Vault保存并通过BlobRef关联；
- AC-406：D4不进入业务事件、日志、MCP或导出上下文；
- AC-407：导出、备份、恢复和删除行为可解释并可验证。

## F. MVP核心通过条件

必须同时满足：

1. 完成同一Goal的Strategy v1和v2两轮真实执行；
2. v2明确引用v1的执行、结果或反馈；
3. 至少一次真实反馈导致策略发生可解释变化；
4. 外部Agent可以维护资产和策略，而App不内置模型推理；
5. 更换Agent后历史仍可继续；
6. 数据可以无损导出并重建；
7. 用户认为策略连续性或复盘价值高于一次性对话；
8. 没有Critical/High未缓解的数据完整性或安全缺陷。

## G. 不计为通过的证据

以下只能证明局部能力：

- synthetic/fake模型输出；
- widget或Robolectric测试；
- 一次成功的MCP调用；
- 一次策略生成但没有执行结果；
- Agent声称策略有效；
- APK成功构建；
- 桌面或Windows smoke；
- 没有绑定exact commit的截图。
