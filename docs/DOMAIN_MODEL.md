# 领域概念模型 v0.2

状态：revised MVP concept model；不规定数据库和具体MCP SDK。

## 1. 核心概念

| 概念 | 含义 | 关键属性 |
|---|---|---|
| Person | Personal OS服务主体 | 身份与数据所有权 |
| Domain | 外形、健身等领域 | 名称、范围、风险 |
| PersonalAsset | 用户已拥有的条件、资源、能力或长期信息 | 类型、值、单位、来源、有效期、版本 |
| Goal | 希望达到或维持的结果 | 成功指标、时间、优先级、状态 |
| Constraint | 限制策略和行动的条件 | 类型、强度、有效期、可协商性 |
| Observation | 某一时间点的记录 | 值、来源、质量、敏感度 |
| Claim | 可被支持、质疑、过期或撤回的陈述 | 证据、可信状态、有效期 |
| Strategy | Agent为Goal提出的总体方法 | 假设、条件、预期结果、评价指标、版本 |
| Plan | Strategy在有限周期内的执行展开 | 起止时间、预算、状态 |
| Task | 最小可执行行动 | 完成条件、截止/频率、停止条件 |
| Execution | Task真实发生的情况 | 完成、跳过、偏离、时间、原因 |
| Outcome | 执行后可观测的结果 | 指标、基线、结果、时间、来源 |
| Feedback | 用户主观体验和评价 | 内容、评分、时间、对象引用 |
| Review | 对Strategy、Execution和Outcome的结构化复盘 | 结论、证据、未知项、下一步 |
| AgentRef | 外部Agent或Harness身份 | 名称、类型、版本、实例标识 |
| AgentSession | Agent访问Personal OS的短期会话 | 权限、状态、创建/失效时间 |
| Attachment | 加密保存的大对象 | BlobRef、类型、时间、敏感度 |

## 2. 信息类型

- UserFact：用户明确陈述并确认；
- Observation：人工、设备或导入观测；
- DeterministicOutcome：可以直接核验的结果；
- SubjectiveFeedback：用户感受和评价；
- AgentInference：Agent对事实意义的推断；
- Recommendation：Agent提出的行动；
- Unknown：信息不足；
- Conflict：来源或结论冲突。

信息类型和D0–D4敏感度是两条独立轴。

## 3. 最小关系

- Person拥有PersonalAssets、Goals和Constraints；
- Goal拥有Strategy时间线；
- Strategy引用Goal、相关资产、假设和评价指标；
- Strategy可以引用predecessor形成版本链；
- Plan实现一个Strategy并包含Tasks；
- Execution记录Task真实发生了什么；
- Outcome与Feedback评价Strategy或Plan；
- Review引用Strategy、Execution、Outcome和Feedback；
- Review可以产生Strategy新版本；
- AgentSession授权Agent读取或提交领域命令；
- Agent写入通过Source/AgentRef保留来源；
- Attachment通过BlobRef与资产、Observation或Outcome关联。

## 4. 生命周期

### Goal

draft → active → paused → achieved / abandoned / replaced

### Strategy

proposed → accepted / rejected  
accepted → active  
active → completed / abandoned  
completed → effective / ineffective / inconclusive / execution_insufficient  
ineffective或inconclusive → revised  
effective → reusable或revised

### Plan

draft → approved → active → paused → completed / stopped

### Task

pending → completed / skipped / blocked / cancelled

### AgentSession

requested → active → expired / revoked / closed

## 5. 不变量

1. Strategy必须引用Goal；
2. Active Strategy必须有评价指标；
3. Agent创建的Strategy初始为proposed；
4. Execution只能记录真实行为；
5. Agent不得修改既有Execution或DeterministicOutcome；
6. Review不得覆盖历史，只能产生新记录；
7. Strategy不能仅凭Agent声明进入effective；
8. AgentInference不能覆盖UserFact；
9. 所有Agent写入必须关联AgentRef和Session；
10. D4不能进入领域对象、MCP和导出上下文；
11. 给定同一事件序列必须重建相同状态。

## 6. 与技术层分离

领域模型不包含：

- OpenAI、Anthropic、Codex或Claude专属类型；
- Prompt和模型参数；
- MCP传输细节；
- SQLite表；
- Flutter Widget；
- Graphiti或向量索引。

Agent Gateway把领域Queries/Commands映射为MCP，但不能改变本模型语义。
