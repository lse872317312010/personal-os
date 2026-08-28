# 远程分支与仓库真相审计

更新时间：2026-08-28  
仓库：lse872317312010/personal-os  
审计分支：codex/p0-repo-truth-and-branch-audit

## 结论摘要

本次刷新只记录可由 GitHub 当前远程状态直接证明的事实：

- main exact commit：`8eda400471e51a3137ddde3160073db402e2da5d`。
- main commit message：`fix(android): clear P0 build blockers and restore formatter compliance (#70)`。
- 远程分支总数：61（含 `main` 和本审计分支）。
- 当前开放 PR 仅为 #66、#68、#69；#69 仍为 open、未合并，head ref 为 `codex/p0-repo-truth-and-branch-audit`，base ref 为 `main`。
- 本审计分支已通过 merge commit `e8d6c67e617925519ca15fd7c59aa8b0096477dc` 纳入 main exact commit `8eda400471e51a3137ddde3160073db402e2da5d`，随后仅刷新本 PR 的 truth docs。
- 本次没有删除任何分支，也不基于旧快照声明任何分支“可安全删除”。

旧快照中的 main、PR、Actions/Release pending 与 ahead/behind 断言均已移除；本文件只保留本次重新读取的远程事实。

## P0 build-blocker 与 Android Release 证据

P0 修复与发布链已经满足 exact-commit 条件：

- [main commit `8eda400471e51a3137ddde3160073db402e2da5d`](https://github.com/lse872317312010/personal-os/commit/8eda400471e51a3137ddde3160073db402e2da5d) 是 PR #70 合入后的 P0 build-blocker 修复。
- 同一 SHA 的 [Flutter Android APK Release run #33130602184](https://github.com/lse872317312010/personal-os/actions/runs/33130602184) 为 `completed/success`。
- “Verify and package Android debug APK” job 成功；其中 Test and build、Prepare and verify release assets、Upload workflow artifact 步骤均成功。
- “Publish rolling GitHub Release” job 成功；其中 Checkout release commit、Download verified assets、Verify downloaded assets、Publish rolling release 步骤均成功。
- 对应 [android-latest rolling Release](https://github.com/lse872317312010/personal-os/releases/tag/android-latest) 发布于 2026-08-28 00:52:35 UTC，状态为非 draft、prerelease，包含三项上传完成的资产：
  - `personal-os-latest-debug.apk`，157,024,141 bytes，GitHub digest `sha256:4ebcc8df0d1285294bda887db6b4dd4a256be713ee61064ca75e15b3616ae580`；
  - `personal-os-latest-debug.apk.sha256`，103 bytes，GitHub digest `sha256:ec15488f529f9d55d7f0297c9464fec7aacf4e1339df7d2dc6e067238372de32`；
  - `personal-os-latest-debug.provenance.json`，308 bytes，GitHub digest `sha256:d7bb387990ada6c0b1e6fe1d279ad315a1caad7afef4f62836504734d7d0034d`。

以上只证明该精确提交的自动化测试、Android debug APK 构建、资产校验和 rolling Release 发布成功；不证明 Redmi Turbo 真机、SQLCipher/Keystore production behavior、冷启动恢复、Camera/native blob runtime 或真实模型已经验证。

## 当前开放 PR

| PR | Head ref | 结论 |
|---|---|---|
| #66 | `codex/p0-secure-vault-cold-start` | open；保留，等待独立审查/合并结论 |
| #68 | `codex/p0-redmi-dogfood-verification` | open；保留，等待 Redmi dogfood 证据 |
| #69 | `codex/p0-repo-truth-and-branch-audit` | open、未合并；本次只同步 main 并刷新 truth docs |

PR 是否开放是保留分支的充分理由，但 PR 已关闭或旧标题含 superseded 并不是删除分支的充分证据。

## 分支治理规则

审计脚本是只读的，不包含删除 ref 的逻辑：

~~~text
python3 tool/audit_remote_branches.py --repo lse872317312010/personal-os --format text
~~~

任何后续删除必须在删除当时重新读取：

1. 当前 main SHA；
2. branch tip SHA；
3. `compare(main, branch)` 的 ahead/behind；
4. 与 branch tip 精确匹配的 PR head 和 merge 状态；
5. branch tip 是否出现新的提交或新的开放 PR。

只有 branch tip 已被当前 main 完整包含、与 main 完全相同，或精确等于已合并 PR head 且无后续提交时，才可进入安全删除清单。当前文档不复用 2026-08-24 的旧 compare 数值，也不授权删除任何分支。
