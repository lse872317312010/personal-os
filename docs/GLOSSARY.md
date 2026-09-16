# 术语表

| 术语 | 定义 | 不等于 |
|---|---|---|
| Personal OS | 用户拥有的个人资产、目标、策略、执行和结果闭环 | 聊天机器人或普通习惯App |
| Agent-agnostic | 任意兼容Agent可读取和延续同一历史 | 所有Agent输出都相同 |
| PersonalAsset | 用户已有条件、资源、能力和长期信息 | 只有文件和照片 |
| Goal | 希望达到或维持的可评价结果 | 模糊愿望 |
| Constraint | 限制可选策略的现实条件 | 普通偏好文本 |
| Observation | 对某时点状态的记录 | 对原因的推断 |
| UserFact | 用户明确陈述并确认的信息 | Agent猜测 |
| AgentInference | Agent根据上下文形成的推断 | 已验证事实 |
| Strategy | 为Goal选择的总体方法、假设和评价框架 | 单个Task |
| Strategy Version | 对前序Strategy的可追溯修订 | 覆盖旧策略 |
| Plan | Strategy在有限周期内的行动展开 | 无限期愿望 |
| Task | 可执行、可验证的最小行动 | 泛泛建议 |
| Execution | Task实际完成、跳过、偏离或阻塞的记录 | 计划状态 |
| DeterministicOutcome | 可直接核验的执行结果 | Agent对效果的评价 |
| SubjectiveFeedback | 用户的感受、偏好和主观评分 | 客观测量 |
| Review | 基于执行和结果对Strategy进行复盘 | 仅统计完成率 |
| AgentRef | 外部Agent/Harness的来源身份 | 模型厂商锁定 |
| AgentSession | Agent访问Personal OS的短期授权会话 | 永久账户权限 |
| MCP | Agent访问Personal OS资源和工具的标准协议 | 推理模型或业务内核 |
| Context Bundle | 提供给Agent的版本化上下文包 | 完整数据库备份 |
| Proposal Bundle | Agent返回的资产、策略、计划或复盘提案 | 绕过验证的数据库写入 |
| EventStore | 保存不可变业务变化历史的权威日志 | Agent聊天历史 |
| Projection | 由事件重建的当前查询视图 | 独立权威事实 |
| BlobRef | 加密附件的不透明引用 | 文件系统路径 |
| Dogfooding | 创建者用真实目标验证两轮闭环 | synthetic演示 |
| local-first | 本地数据可独立使用并保持权威 | 永远不允许联网 |
| D0–D4 | 数据泄露或误用风险等级 | 信息真实性 |
