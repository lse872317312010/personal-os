# 远端分支只读审计（2026-09-04）

仓库：`lse872317312010/personal-os`  
审计基线：`main@5ff7a1e44c07710c465c1367cb6b9b510a1d3f79`

## 当前事实

- 远端分支共 67 个，包含 `main`；非 `main` 分支 66 个。
- GitHub Pull Requests 页面显示 0 个开放 PR、69 个已关闭 PR。
- 对 66 个非 `main` 分支逐一执行 `compare(main, branch)`，全部显示
  `diverged`；没有任何分支满足 `ahead_by == 0`。
- 该结果符合仓库长期使用 squash merge 的历史：已合并 PR 的原始 head
  commit 不会成为 `main` 的祖先。
- 本次没有删除、改名或移动任何远端分支。

因此，`git branch --merged main` 或仅依据 ahead/behind 的清理方式不适用于
当前仓库。它会遗漏已经 squash 合并的分支，也不能证明带独立提交的分支内容已
被主线覆盖。

## 可重复审计

只读审计器：

```sh
python3 tool/audit_remote_branches.py \
  --repo lse872317312010/personal-os \
  --format text
```

工具依赖已认证的 GitHub CLI，并对每个分支同时检查：

1. 当前 `main` SHA；
2. 当前 branch tip SHA；
3. `compare(main, branch)` 的 ahead/behind；
4. 使用该 head ref 的全部 PR；
5. branch tip 是否精确等于已合并 PR 的 head SHA；
6. 是否存在开放 PR或合并后新增提交。

工具只输出以下保守分类，不包含删除 ref 的功能：

- `SAFE_TO_DELETE`：branch tip 已被 `main` 包含、与 `main` 相同，或精确等于
  已合并 PR 的 head SHA；
- `REVIEW_DELETE_CANDIDATE`：branch tip 精确等于一个明确标记为 superseded
  或 rejected 的未合并关闭 PR；
- `RETAIN`：其余所有情况，包括数据缺失、开放 PR、合并后新增提交及无法证明
  已覆盖的独立工作。

## 删除门禁

任何删除操作都必须使用删除当时重新生成的报告；本快照不授权删除。执行者还需
逐项确认：

- 报告中的 `main_sha` 仍是当前主线；
- branch tip 未在审计后变化；
- `SAFE_TO_DELETE` 的证据来自精确 SHA，而不是相似标题或文件名；
- 不删除 `main`、活动发布标签或任何存在开放 PR 的分支；
- `REVIEW_DELETE_CANDIDATE` 必须人工确认后才能删除。

真机 Redmi dogfood 仍是 P0 产品验收阻塞；分支治理不得被误报为真机验证进展。
