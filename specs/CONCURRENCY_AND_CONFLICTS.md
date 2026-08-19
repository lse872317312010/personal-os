# M1 并发与冲突语义 v0.1

状态：accepted

## 原则

- 不采用静默 last-write-wins 处理用户语义；
- 审计顺序与现实发生顺序分离；
- 可交换事件自动合并，不可交换事件显式冲突；
- 冲突本身是领域状态，不是存储错误；
- 自动 Actor 不得替用户解决偏好、目标或授权冲突。

## 并发基础

事件携带 `expected_revision` 和可选 `base_event_id`。写入时：

- 当前 revision 匹配：正常应用；
- 不匹配但事件可交换：应用并保留各自因果关系；
- 不匹配且不可交换：接受到日志但进入 `conflict.detected`，不改变当前业务投影；
- 重复 event_id：幂等忽略。

## 可自动合并

- 对不同对象的独立 Observation；
- 同一 Task 的不同非互斥注释或测量；
- 不改变授权和状态机的附加 Source 引用；
- 只扩展集合且不违反敏感度/用途的元数据。

## 必须显式解决

- 同一 Claim revision 的 confirmed 与 disputed；
- 同一 Goal 的 achieved 与 abandoned；
- 同一 Plan 的 completed 与 stopped；
- Preference 权重的不同修改；
- Consent 的 scope 修改与 revoke；
- 删除请求与新的派生/分享操作；
- 任何会改变当前 Recommendation 的冲突。

## 冲突事件

- `conflict.detected`：记录对象、候选 revisions、冲突类型和检测规则；
- `conflict.resolution.proposed`：提供 keep/merge/replace/defer 选项；
- `conflict.resolved`：用户或明确规则选择结果；
- `conflict.dismissed`：确认冲突不影响当前投影。

解决不得删除候选历史；current pointer 只在 `conflict.resolved` 后更新。

## 删除优先级

一旦 `deletion.requested` 生效，目标进入 deletion barrier：后续 read/derive/share 默认拒绝。与删除并发的新处理不能靠记录时间抢先，除非其 occurred_at 更早且有当时有效 Consent；即便如此，删除范围仍传播到其派生内容。

