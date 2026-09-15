# 需求基线

版本：0.2  
状态：Android Agent-driven MVP requirements accepted

## 1. 系统需求

| ID | 需求 | MVP验收 |
|---|---|---|
| SYS-001 | 保存带来源、时间、版本和可信状态的个人资产 | 可创建、修订、归档并查看历史 |
| SYS-002 | 统一表达Goal、Constraint、Strategy、Plan、Task、Execution、Outcome和Review | 一个Goal可追踪到两轮策略和结果 |
| SYS-003 | 区分UserFact、Observation、DeterministicOutcome、SubjectiveFeedback、AgentInference、Recommendation和Unknown | UI和导出均保留类型 |
| SYS-004 | 所有业务修改使用事件表达，不覆盖历史 | 能回答何时、由谁、为何变化 |
| SYS-005 | Android Vault是MVP唯一权威端 | Agent离线或更换后数据不丢失 |
| SYS-006 | 数据可无损导出、备份、恢复和删除 | 导出重建后保持引用关系 |
| SYS-007 | 模型或Agent不可用不影响本地数据管理 | 本地查看、纠错和导出仍可用 |

## 2. Agent与接口需求

| ID | 需求 | MVP验收 |
|---|---|---|
| AGT-001 | 系统通过厂商无关接口连接外部Agent/Harness | 核心Schema无厂商类型 |
| AGT-002 | MCP提供读取目标上下文、资产和策略历史的能力 | Agent可取得一次完整闭环所需上下文 |
| AGT-003 | MCP允许读写Agent维护资产、创建策略、计划和复盘 | 写入经过Application Commands |
| AGT-004 | Agent写入携带agent、来源、时间、信息类型和Schema版本 | 任一Agent写入可追溯 |
| AGT-005 | 支持只读和读写Session | 只读Session写入被拒绝 |
| AGT-006 | Agent推断不能覆盖用户事实或确定性结果 | 非法状态转换失败关闭 |
| AGT-007 | 更换Agent后可延续同一目标和历史 | 第二个Agent可读取并修订第一个Agent的策略 |
| AGT-008 | 支持Context Bundle与Proposal Bundle | 无实时MCP时仍可完成一次交换 |
| AGT-009 | D4秘密不得进入MCP资源、工具参数或导出上下文 | contract tests拒绝D4 |

## 3. 策略生命周期需求

| ID | 需求 | MVP验收 |
|---|---|---|
| STR-001 | Strategy引用Goal、假设、适用条件、预期结果和评价指标 | 缺少Goal或指标时拒绝激活 |
| STR-002 | Strategy使用显式版本和前序引用 | 可展示v1到v2变化 |
| STR-003 | Agent提出的Strategy默认为Proposed | 用户接受后才进入Active |
| STR-004 | Plan必须有限周期并包含可执行Task | 每个Task有完成和停止条件 |
| STR-005 | Execution记录完成、跳过、偏离及原因 | 不允许Agent伪造历史完成状态 |
| STR-006 | Outcome区分确定性结果和主观反馈 | Review分别引用两类证据 |
| STR-007 | Review区分Effective、Ineffective、Inconclusive和ExecutionInsufficient | 结论具有明确证据引用 |
| STR-008 | Strategy新版本说明保留、删除和修改了什么 | 用户可理解修订理由 |
| STR-009 | 策略有效性不能仅由Agent声明 | 必须存在Execution/Outcome或标为未验证 |

## 4. Android体验需求

| ID | 需求 | MVP验收 |
|---|---|---|
| AND-001 | 用户可以在手机建立和维护资产、目标和约束 | 离线可完成 |
| AND-002 | 用户可以建立、关闭和查看Agent Session | 锁屏或Vault关闭后Session失效 |
| AND-003 | 用户可以审核Agent写入的资产修订和策略 | 可接受、修改或拒绝 |
| AND-004 | App显示今日Task并快速记录结果 | 常用反馈不超过必要步骤 |
| AND-005 | App显示Goal→Strategy→Plan→Execution→Outcome→Review链路 | 引用可追踪 |
| AND-006 | App显示策略版本差异和复盘结论 | v1/v2可以对比 |
| AND-007 | App支持加密附件并通过BlobRef关联 | 业务记录不暴露文件路径 |
| AND-008 | 冷启动、杀进程和重启后恢复当前状态 | Redmi真机验证 |

## 5. 首个领域切片

首个切片可从外形或健身选择，但领域逻辑不得承担推理。领域层只定义可记录资产、指标、任务和安全边界。

外形候选输入：文字、照片、衣物、预算、审美目标、用户反馈。  
健身候选输入：身体状态、训练记录、时间、器械、目标、恢复和用户反馈。

Agent负责分析和提出策略；Personal OS负责结构化保存、执行监督和结果记录。

## 6. 非功能需求

| ID | 需求 |
|---|---|
| NFR-001 | Core不依赖Flutter、Android、MCP SDK或模型厂商 |
| NFR-002 | UI、MCP和文件导入共享相同Application API |
| NFR-003 | 关键事件可审计且不可静默覆盖 |
| NFR-004 | 日常本地写入原子、快速且可恢复 |
| NFR-005 | SQLCipher、Blob和Keystore失败关闭 |
| NFR-006 | JSON/JSONL Schema明确版本并向后兼容 |
| NFR-007 | MCP错误稳定、结构化且不泄露内部路径、密钥和原始异常 |
| NFR-008 | 第一阶段不以后台常驻作为正确性前提 |

## 7. 延后需求

- Windows与其他客户端；
- 多设备E2EE；
- 云端Relay；
- 自动策略选择；
- 多Agent编排；
- 高级披露控制；
- 时态知识图谱与向量索引；
- 个人模型训练；
- 自动外部行动。
