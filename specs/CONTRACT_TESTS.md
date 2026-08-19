# M1 契约测试清单 v0.1

状态：draft / implementation-independent

## 确定性与幂等

- CT-001：相同有效事件序列重放得到字节语义等价的核心状态；
- CT-002：同一 event_id 重复输入只生效一次；
- CT-003：Snapshot + 增量与完整重放等价；
- CT-004：未知非关键字段被保留或安全忽略，不改变既有语义；
- CT-005：未知 event_version 被隔离，不部分应用。

## 状态机

- CT-101：每个合法转换得到目标状态；
- CT-102：非法转换不改变状态并返回稳定 reason code；
- CT-103：terminal 对象不能被旧事件复活；
- CT-104：completed Task 缺少 ExecutionRecord 时拒绝；
- CT-105：active Plan 缺少有效 Consent 或有限周期时拒绝。

## 时间、版本与冲突

- CT-201：effective/occurred 与 recorded 时间分别保留；
- CT-202：迟到事件触发受影响区间重投影，不篡改审计顺序；
- CT-203：两个并发 revision 不按“最后写入”静默覆盖；
- CT-204：withdrawn/expired/superseded Claim 不进入当前建议；
- CT-205：引用固定 revision，不因 later revision 静默漂移。

## 授权与隐私

- CT-301：缺失、过期、撤销或用途不兼容 Consent 的事件被拒绝；
- CT-302：Consent scope 扩大必须使用新 Consent；
- CT-303：D4 在对象、事件、错误和审计输出中均被拒绝；
- CT-304：R3 外部动作在 MVP 中只能产生草案；
- CT-305：非用户 Actor 不能接受 Review 或代替用户授予 Consent。

## 纠错与删除

- CT-401：纠错创建新 revision，旧版本仍可审计但不参与当前决策；
- CT-402：L2 删除后原始内容不可读取或从 Snapshot 恢复；
- CT-403：tombstone 不含原内容或可重识别 hash；
- CT-404：引用已删对象返回显式 unavailable；
- CT-405：删除后新的派生处理被阻止；
- CT-406：partial deletion 清楚报告未完成范围与原因。

## 端到端验收

- CT-501：S1 产生 active Plan 和可追溯 Task；
- CT-502：S2 的反馈只在 Review accepted 后修改当前 Claim；
- CT-503：S3 的 revoke 阻止新处理且删除不泄露原内容；
- CT-504：S4 的重复/迟到事件保持幂等和审计真实性。

M1 退出前，每条测试必须映射到至少一个需求、验收标准或安全不变量。

