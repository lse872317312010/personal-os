# M1 端到端事件序列 v0.1

状态：draft for contract tests

事件只展示顺序和关键引用，不代表界面流程。

## S1：从基线到计划批准

1. `consent.requested(C1, D3 image analysis, one session)`
2. `consent.granted(C1)`
3. `source.registered(S1, image metadata only)`
4. `observation.recorded(O1, source=S1, consent=C1)`
5. `claim.proposed(CL1, evidence=O1)`
6. `claim.confirmed(CL1)`
7. `goal.created(G1)` → `goal.activated(G1)`
8. `baseline.created(B1, refs=[O1, CL1])`
9. `opportunity.identified(OP1, baseline=B1, goal=G1)`
10. `recommendation.created(R1, opportunity=OP1)`
11. `plan.drafted(P1, recommendation=R1)`
12. `consent.requested(C2, approve plan P1)` → `consent.granted(C2)`
13. `plan.approved(P1, consent=C2)` → `plan.activated(P1)`
14. `task.planned(T1, plan=P1)`

预期投影：P1 active；T1 planned；CL1 confirmed；C1/C2 granted。任何缺失 Consent 的 D3 事件或 plan.approved 被拒绝。

## S2：执行反馈导致模型修订

1. `task.planned(T1)` → `task.ready(T1)` → `task.in_progress(T1)`
2. `execution.recorded(E1, task=T1, actual=true)`
3. `task.completed(T1, execution=E1)`
4. `outcome.recorded(O2, relates_to=T1)`
5. `review.created(RV1, baseline=B1, plan=P1, outcomes=[O2])`
6. `review.user_reviewed(RV1)` → `review.accepted(RV1)`
7. `model.revision.proposed(MR1, claim=CL1 → CL2, cause=RV1)`
8. `claim.proposed(CL2, supersedes=CL1)` → `claim.confirmed(CL2)`
9. `claim.withdrawn(CL1, superseded_by=CL2)`
10. `model.revision.accepted(MR1)`
11. `plan.completed(P1)`

预期投影：CL2 是当前 Claim；CL1 仅保留历史；Review 可解释修订原因；P1 completed。

## S3：撤销授权与删除

1. `consent.revoked(C1)`
2. 一个新的 `observation.recorded(O3, consent=C1)` 到达 → 拒绝，不产生 O3
3. `deletion.requested(DR1, scope=source S1 and raw blob)`
4. 投影立即将相关原始内容标记 unavailable_pending_deletion
5. 存储执行物理擦除
6. `deletion.completed(DR1, tombstone=TS1, erased=[S1 blob], retained=[minimal audit])`
7. 依赖 S1 的 Claim 重新评估：`claim.withdrawn(CL1)` 或标记 evidence_unavailable
8. 新的 Snapshot 排除已删内容，仅包含 tombstone/hash-free audit reference

预期投影：原始内容不可读、不能继续派生；最小审计说明删除发生但不泄露被删内容。

## S4：重复与迟到事件

1. `task.completed(T1, event_id=E10)` 被接受；
2. 相同 E10 再次到达 → 幂等忽略；
3. 一个 occurred_at 更早、recorded_at 更晚的 `constraint.recorded(CN1)` 到达；
4. 系统保留审计顺序，并从受影响时间点重新计算领域投影；
5. 若 CN1 使历史 plan.approved 在当时无效，产生 conflict/validation result，不删除历史事件。

