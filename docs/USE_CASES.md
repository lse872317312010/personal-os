# 端到端用户场景

状态：Android Agent-driven MVP accepted

## UC-01：建立个人资产与目标

触发：用户希望改善一个真实目标。

主流程：

1. 用户在Android App创建Goal；
2. 记录期望结果、评价指标、时间和约束；
3. 用户录入文字、数值、照片或文件；
4. 系统将其保存为PersonalAsset、Observation或Attachment；
5. 每条记录保留来源、时间、信息类型和敏感度；
6. 用户可以修订、归档或标记Unknown；
7. 系统生成当前目标上下文。

结果：形成可供Agent读取、但不包含推理结论的权威上下文。

## UC-02：连接外部Agent

触发：用户准备让Codex或其他Agent处理目标。

主流程：

1. 用户解锁Vault并建立Agent Session；
2. 选择只读或读写；
3. App显示连接地址、配对信息和Session状态；
4. Agent通过MCP查询活动目标；
5. Agent读取与目标关联的资产、约束和历史；
6. 所有调用记录agent、工具、时间、结果和Session；
7. 锁屏、用户关闭或Session到期后访问失效。

替代流程：无法实时连接时，App导出Context Bundle，并导入Agent返回的Proposal Bundle。

## UC-03：Agent维护资产

触发：Agent从用户对话、文件或既有历史中发现需要新增或修订的资产。

主流程：

1. Agent调用upsert_asset或record_observation；
2. 写入包含来源、信息类型、时间和修订理由；
3. Application Core验证版本和状态；
4. 新事实与旧事实冲突时生成修订或Conflict，而非静默覆盖；
5. App向用户展示Agent产生的变化；
6. 用户可以接受、修改、否定或归档。

边界：AgentInference不能直接成为UserFact或DeterministicOutcome。

## UC-04：Agent生成策略与计划

触发：目标上下文已经足够。

主流程：

1. Agent读取Goal、Constraint、PersonalAsset和相关历史；
2. Agent创建Proposed Strategy；
3. Strategy包含假设、适用条件、预期结果和评价指标；
4. Agent创建有限周期Plan与Tasks；
5. 用户在App查看来源、依据和风险；
6. 用户接受、修改或拒绝；
7. 接受后Strategy进入Active，Plan进入执行期。

## UC-05：App监督执行

触发：存在Active Plan。

主流程：

1. App展示今日Task；
2. 用户记录完成、跳过或偏离；
3. 系统保存时间、实际值、困难、停止原因和附件；
4. 用户记录主观反馈；
5. 设备或用户输入确定性Outcome；
6. App不根据这些数据自行推理策略；
7. 周期结束后标记Review due。

## UC-06：Agent复盘并修订策略

触发：计划周期结束或用户主动复盘。

主流程：

1. Agent读取原Strategy、Plan、Executions、Outcomes和Feedback；
2. Agent写入Review；
3. Review区分Effective、Ineffective、Inconclusive和ExecutionInsufficient；
4. Agent说明哪些结论来自确定性结果，哪些属于推断；
5. Agent创建Strategy新版本；
6. 新版本引用前序策略并说明保留、删除和修改；
7. 用户确认后进入下一轮。

## UC-07：更换Agent继续历史

触发：用户更换模型厂商或Harness。

主流程：

1. 新Agent建立独立Session；
2. 通过相同MCP Schema读取Goal和历史；
3. 新Agent能够理解前一个Agent留下的Strategy、Review和证据引用；
4. 新Agent创建兼容的新版本；
5. Personal OS不迁移数据库，也不丢失历史。

## UC-08：导出与恢复

1. 用户导出带Schema版本的JSON/JSONL和附件清单；
2. 系统验证引用完整性；
3. 在清空或新安装环境中恢复；
4. Goal、Strategy版本、Execution、Outcome和Review链保持一致；
5. Markdown只作为阅读副本，不替代无损格式。

## MVP完整性检查

MVP必须回答：

- 个人资产和目标如何建立？
- Agent如何通过统一接口读取？
- Agent如何维护资产而不篡改历史？
- Strategy如何进入Plan？
- App如何监督真实执行？
- 确定性结果和主观反馈如何区分？
- 下一轮策略如何引用上一轮结果？
- 更换Agent后如何保持连续？
- 用户如何导出、恢复和删除？
