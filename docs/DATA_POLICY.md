# 数据分类与处理规则

状态：MVP产品边界已接受；具体保留周期可在dogfooding中调整。

## 1. 数据等级

| 等级 | 含义 | 示例 | 默认处理 |
|---|---|---|---|
| D0 公开 | 不指向私人身份的公开材料 | 通用术语、公开知识 | 可进入普通文档 |
| D1 内部 | 低敏感个人配置 | UI偏好、抽象任务状态 | 私有保存，按需提供 |
| D2 私密 | 描述个人偏好、目标或连续行为 | 目标、策略、执行历史、主观反馈 | 进入Vault，可授权Agent使用 |
| D3 高敏感 | 泄露可能造成明显伤害 | 原始照片、健康、关系、精确位置、财务明细 | 加密保存，明确用途和审计 |
| D4 秘密 | 可直接取得账户或系统控制权 | 密码、验证码、API key、私钥、恢复码 | 禁止进入业务事件、导出上下文和Agent历史 |

MVP暂不实现复杂的渐进披露。用户建立一个Agent Session时选择只读或读写，并明确会话是否可访问D2/D3；D4永不作为业务上下文提供。

## 2. 信息类型

敏感度和信息可信度是独立维度。每条核心记录必须标记一种信息类型：

- UserFact：用户明确陈述并确认；
- Observation：人工、设备或导入来源记录的观测；
- DeterministicOutcome：可直接核验的执行结果；
- SubjectiveFeedback：用户的感受、评分或偏好；
- AgentInference：Agent推断；
- Recommendation：Agent建议；
- Unknown：信息不足；
- Conflict：来源或结论存在冲突。

AgentInference和Recommendation不能覆盖UserFact、Observation或DeterministicOutcome。

## 3. 权威资产

Android Vault保存以下权威资产及其事件历史：

- PersonalAsset；
- Goal与Constraint；
- Observation；
- Strategy及版本；
- Plan与Task；
- Execution；
- Outcome；
- Review；
- Attachment/Blob；
- Agent Session与调用审计。

派生搜索索引、向量、图谱和摘要不是权威事实，必须能够从事件和资产重建。

## 4. 来源与时间

每条写入至少包含：

- source_type与source_ref；
- recorded_at；
- occurred_at或effective_at；
- information_type；
- sensitivity；
- schema_version；
- actor/agent；
- causation/correlation；
- 被修订对象的版本引用。

修订创建新事件；历史执行和结果不得原地改写。

## 5. Agent处理规则

1. Agent只能通过Application Commands写入；
2. MCP不得暴露SQL、数据库路径、密钥或原始内部表；
3. Agent维护资产时必须说明来源；
4. Agent创建Strategy时必须引用Goal并提供评价指标；
5. Agent创建Review时必须引用Execution和Outcome；
6. Agent不能自行声称一个策略已被验证；
7. 只读Session不得产生业务写入；
8. 读写Session的所有调用进入审计记录；
9. 删除、覆盖历史和高风险外部行动不属于MVP Agent能力。

## 6. 导入、导出与附件

- JSON/JSONL是权威结构化导出格式；
- Markdown用于人类查看，不作为无损权威格式；
- Context Bundle只包含某次Agent任务需要的结构化快照；
- Proposal Bundle保存Agent返回的资产修订、策略、计划或复盘；
- 图片和文件由Encrypted Blob Vault独立保存并通过不透明引用关联；
- 导出必须携带schema版本和引用完整性信息。

## 7. 当前待定

- D2/D3面向不同Agent的精细字段授权；
- 原始照片默认保留周期；
- 远程MCP和云端Agent的认证方式；
- 长期策略效果是否需要独立的最高敏感等级；
- 多设备同步和中继；
- 派生图谱/向量索引的实现。
