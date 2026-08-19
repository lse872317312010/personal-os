# 使用 M1 事件序列走查推荐架构

状态：first pass complete

## S1：基线到计划批准

- D3 原图进入 Encrypted Blob Vault，不进入事件 payload；
- Policy Engine 验证 C1，Application Core 在单事务中写 event、projection、outbox；
- Relay 只见密文 envelope；
- plan.approved 再次验证 C2；缺失 Consent 时事务拒绝且不产生业务投影。

结论：推荐架构可满足 S1；要求数据库层支持 event/projection/outbox 原子性。

## S2：执行反馈到模型修订

- 本地离线完成 Task 和 Outcome；
- Review accepted 前 Model Gateway 输出只能处于 proposed；
- accepted 后生成新 Claim revision，旧 Claim withdrawn；
- Projection Store 重建 current pointer，Event Store 保留历史。

结论：模型不能直接写投影，必须经 Core command/event 边界。

## S3：撤销与删除

- consent.revoked 先更新 Policy projection；
- 新 D3 写入被拒绝；
- deletion barrier 使 Blob/索引/Snapshot 不可用；
- Blob Key 销毁、本地清理、密文 Relay 删除并生成 receipts；
- 受影响 Claim 标记 evidence_unavailable/withdrawn。

结论：删除是跨组件 Saga，但每个本地步骤必须幂等；需要专门 deletion coordinator。

## S4：重复与迟到事件

- Event Store 以 event_id 保证幂等；
- Inbox 检测 device_seq 缺口；
- 迟到事件保留 occurred/recorded 时间并触发受影响投影重算；
- 语义冲突进入 conflict.*，Relay 不裁决。

结论：Relay 无需理解业务冲突；客户端 Core 必须支持增量重投影或安全全量重放。

## 走查产生的架构要求

- 单设备只有一个逻辑 writer 队列，规避 SQLite 多 writer 争用；
- event + projection + outbox 原子提交；
- Blob 与事件引用存在提交/回滚协议；
- Model Gateway 永远通过 Core command API；
- deletion coordinator、sync worker、projection rebuilder 是独立职责；
- Restricted Collector 使用 write-only envelope，不获得历史解密能力。

