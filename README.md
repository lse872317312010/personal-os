# Personal OS

一个长期演进的 **AI-native 个人决策操作系统**。

它不是单一的健身、饮食、外貌或社交 App，而是把个人目标、真实状态、约束、行动、反馈和长期记忆连接起来，持续帮助用户做出更好的决策。首位 dogfooding 用户是项目创建者本人，未来保留产品化与商业化可能。

## 当前阶段

项目已完成 **M0 产品章程与范围冻结**，进入 **M1 Core Data Model & Event Log**。M1 只冻结核心语义和事件契约，仍不提前锁定 Flutter、Rust、数据库或模型供应商。

## 首批领域

1. 健身与身体状态
2. 饮食与营养
3. 外形优化：护肤、发型、穿搭、体态与形象表达
4. 社交与关系优化

社交关系模块使用 `V × T × A × M` 漏斗作为分析框架：

- `V`：个人综合价值
- `T`：有效社交流量池
- `A`：可得性与接触机会
- `M`：双向匹配程度

所有关系设计仅面向成年人，并以合法、双方明确自愿、尊重边界为硬约束。

## 北极星目标

建立一个可信、可解释、可审计、可持续学习的个人决策闭环：

`感知现状 → 明确目标 → 识别差距 → 生成方案 → 执行动作 → 记录结果 → 复盘校准`

系统最终应当做到：

- 形成统一但可分域演进的个人状态模型；
- 把建议转化为可执行、可跟踪、可验证的任务；
- 通过长期反馈进行个性化，而不是只依赖一次性对话；
- 明确区分事实、用户输入、推断、建议与不确定性；
- 让用户始终拥有数据、权限和关键决策的控制权；
- 支持未来扩展到金融投资、职业资本、时间配置、消费与城市/区位选择。

## 近期交付目标

- 固化项目使命、范围、原则与非目标；
- 从 2026-08-17“男士外貌分析”对话提炼真实使用场景和决策链；
- 建立需求池、术语表、风险清单和验收标准；
- 选出一个最小纵向闭环作为 MVP，而不是同时开发所有模块；
- 在需求冻结后再进行技术选型、总体架构和模块接口设计。

## 文档入口

- [项目章程](docs/PROJECT_CHARTER.md)
- [M0 退出评审](docs/M0_EXIT_REVIEW.md)
- [MVP 冻结范围](docs/MVP_SCOPE.md)
- [MVP 验收标准](docs/ACCEPTANCE_CRITERIA.md)
- [发展路线与里程碑](docs/ROADMAP.md)
- [需求基线草案](docs/REQUIREMENTS.md)
- [端到端用户场景](docs/USE_CASES.md)
- [领域概念模型](docs/DOMAIN_MODEL.md)
- [需求追踪矩阵](docs/TRACEABILITY.md)
- [风险与人工确认矩阵](docs/RISK_CONTROL_MATRIX.md)
- [需求优先级方法](docs/PRIORITIZATION.md)
- [术语表](docs/GLOSSARY.md)
- [产品原则与边界](docs/PRODUCT_PRINCIPLES.md)
- [数据分类与处理规则](docs/DATA_POLICY.md)
- [需求提炼清单](docs/REQUIREMENTS_INBOX.md)
- [决策记录](docs/decisions/README.md)
- [M1 核心数据模型](specs/CORE_DATA_MODEL.md)
- [M1 事件日志契约](specs/EVENT_LOG.md)
- [变更记录](CHANGELOG.md)

## 状态

`M1 In Progress / Core Data Model & Event Log`
