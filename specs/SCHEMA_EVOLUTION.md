# M1 Schema 演进 v0.1

状态：accepted

## 版本边界

- 每个对象有 `schema_version`；
- 每种事件有独立 `event_version`；
- 投影规则有 `projection_version`；
- Snapshot 记录上述所有版本，不使用单一“应用版本”替代。

## 兼容分类

| 变化 | 兼容性 | 规则 |
|---|---|---|
| 新增可选字段 | backward compatible | 旧读取器保留或安全忽略 |
| 新增带默认语义字段 | 条件兼容 | 默认值必须不改变旧事件含义 |
| 新增枚举值 | forward-sensitive | 未知值隔离或显示 unknown，不映射到相近值 |
| 字段重命名 | breaking | 新版本 + 显式 upcaster |
| 字段拆分/合并 | breaking | 保留来源和可逆映射说明 |
| 单位/时间语义变化 | breaking | 禁止静默转换 |
| 敏感度降低 | breaking/security | 需要独立决策和重新分类审计 |
| 删除字段 | breaking | 先弃用，确认无历史/导出依赖后再移除 |

## Upcaster

Upcaster 只转换表示，不创造新事实、Consent 或推断。每次转换必须确定、无外部依赖、记录 from/to 版本，并通过 golden event tests。

无法安全转换的事件进入 quarantine；系统可以继续读取其他独立事件，但不能部分应用该事件。

## Unknown 保留

中间节点不得丢弃不认识的字段。若字段可能影响安全、权限、状态或金额，整条事件必须隔离；普通扩展字段可透明保留。

## Projection 升级

新投影规则必须对固定事件集运行新旧差异报告。若 current state 改变，需要说明属于 bug fix、规则变更还是新证据解释，并保留旧投影版本以供审计。

