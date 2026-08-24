# 远程分支与仓库真相审计

更新时间：2026-08-24  
仓库：lse872317312010/personal-os  
审计分支：codex/p0-repo-truth-and-branch-audit

## 结论摘要

本次审计以远程 main 的可读取 ref 为准：

- main exact commit：6d23063c5059174240338a6be11d37949fefbab0
- 观察到远程分支总数：59（含 main），其中 58 个非 main 分支
- 当前没有开放 PR
- 没有执行任何分支删除
- 仅有 3 个分支可以依据 compare(main, branch) 直接证明与 main 完全相同，列入安全删除清单
- 其余分支均保留或列为需要二次确认的删除候选；“存在旧 PR”“PR 已关闭”本身不等于代码已经被 main 覆盖

审计脚本是只读的，不包含删除 ref 的逻辑：

~~~text
python3 tool/audit_remote_branches.py --repo lse872317312010/personal-os --format text
~~~

脚本会重新读取 main、分支 tip、compare 结果和所有 PR，因此删除前必须以删除当时的脚本输出重新确认，不能直接套用本快照。

## 可直接证明安全删除

以下分支在本次 compare 中 ahead_by=0、behind_by=0，分支 tip 与 main 完全相同：

| 分支 | 证据 | 结论 |
|---|---|---|
| codex/p0-android-release-evidence | compare main...branch = identical | 可安全删除 |
| codex/p0-redmi-dogfood-verification | compare main...branch = identical | 可安全删除 |
| codex/p0-secure-vault-cold-start | compare main...branch = identical | 可安全删除 |

这些分支没有独立提交可以丢失。删除前仍应重新运行审计脚本，因为远程分支可能被其他 Agent 移动或重新创建。

## 有明确关闭/替代证据的删除候选

下列分支关联的旧 PR 标题或正文明确写有 superseded、不安全设计、过期快照、不兼容实现等处置结论。它们不是本轮“直接安全删除”清单，只有在脚本证明分支 tip 仍等于对应 PR head、且没有新的 PR/提交后，才可删除：

- feature/wave-19a_I-evidence-chain-v11：#8，superseded by #34
- feature/wave-19b_D-export-screen-wiring：#9，closed: unsafe design
- feature/wave-19c_D-delete-screen-wiring：#10，closed: unsafe stub
- feature/wave-19d_B-backlog-v03-sync：#11，closed: stale roadmap snapshot
- feature/wave-20a_D-volatile-demo-warning：#12，closed: misleading production claim
- feature/wave-20b_A-adr-0011-composition-contracts：#13，closed/superseded
- feature/wave-20c_I-composition-root-audit：#14，superseded by #29
- feature/wave-20d_A-adr-0012-sync-envelope：#15，superseded by #36
- feature/wave-20e_D-settings-stub：#18，closed: roadmap leakage
- feature/wave-20f_I-validate-export-envelope：#16，closed: incompatible validator
- feature/wave-20g_I-evidence-chain-v2：#17，superseded by #34
- feature/wave-20h_I-validate-sync-envelope：#19，superseded by #36
- feature/wave-20i_I-gate-status-aggregator：#20，superseded by #34
- feature/wave-20o_I-persistence-import-audit：#26，superseded by #32
- feature/wave-20p_I-cross-adapter-equivalence：#27，closed: false equivalence
- review/sync-envelope-contract-truthful：#36，superseded by #37
- wave-20j_A-adr-0013-persistence-contract：#21，superseded by #30
- wave-20k_D-theme-toggle-ui：#22，superseded by #35
- wave-20l_A-adr-0014-error-mapping：#23，superseded by #33
- wave-20m_I-persistence-error-mapper：#24，superseded by #33
- wave-20n_I-evidence-error-cause-rule：#25，superseded by #34
- codex/luna-d-source-ingestion-transaction-v2：#60 标记为 superseded；仍需确认其四个独立提交没有未提取价值

脚本将这类分支标记为 REVIEW_DELETE_CANDIDATE，不会自动删除。

## 必须保留或先提取价值的分支

以下分支存在 main 未覆盖的差异，且当前没有足够证据证明删除不会丢失独立实现、测试或文档：

### 当前 Android/B2 方向

- codex/b2-02-controlled-source-entry-20260824
- codex/b2-02-controlled-source-entry-v2-20260824
- codex/b2-03-ingest-appearance-20260824
- codex/b2-dart-controlled-source-port-20260824
- codex/b2-native-source-handoff-20260824
- feat/native-camera-capture
- feat/native-camera-capture-main
- docs/camera-truthfulness

其中：

- #63 feat/native-camera-capture-main 有 merged PR 记录，但 compare 仍显示 14 ahead / 1 behind；这是 merge/squash 历史与分支 tip 的差异，删除前必须由脚本确认 tip 精确等于 merged PR head。
- #64 docs/camera-truthfulness 有 merged PR 记录，但当前分支仍显示 5 ahead / 0 behind，并包含 README、Android README 与 docs/M2_B1_BASELINE.md 的独立提交。它不能按“已合并”直接删除，应先确认这些文档是否已经实际进入 main。
- #62 feat/native-camera-capture 是关闭但未合并的旧实现，不能与 #63 的 merged 分支混同。

### 旧 Wave 分支：无合并/覆盖证据

以下分支仍有独立文件差异，且没有匹配 PR 或没有足够的覆盖证明，保留作为待提取参考：

- feature/wave-11/I-backlog-status
- feature/wave-11/I-ci-hardening
- feature/wave-11/I-evidence-writer
- feature/wave-11/I-fill-g0-static-evidence
- feature/wave-11/I-secretscan-fp
- feature/wave-12/I-build-evidence
- feature/wave-13/D-mode-chip-tests
- feature/wave-13/D-sqlite-composition
- feature/wave-14/D-imagepicker-manifest
- feature/wave-14/D-imagepicker-ui
- feature/wave-15/C-methodchannel-impl
- feature/wave-15/C-real-sqlite-sqlcipher
- feature/wave-16/D-export-delete-recovery-ui
- feature/wave-16/I-adr0008-grep-and-pr-template
- feature/wave-17a_D-export-packager
- feature/wave-17b_D-delete-guard
- feature/wave-17c_D-recovery-verifier
- feature/wave-18a_C-in-memory-blob-store
- feature/wave-18b_B-eventstore-readall
- feature/wave-18c_A-adr-0009-0010
- feature/wave-18d_T-integration-test-skeleton
- feature/wave-B/A-adr-0006-0008
- feature/wave-B/A-backlog-sync-13prs
- feature/wave-B/A-requirements-inbox-0817

这些分支应该在后续按主题重新审计：先把仍有价值的脚本、ADR、测试或安全边界提取成小 PR，再删除空壳分支。当前不删除。

## PR 与主线真相差异

本次 GitHub 读取到：

- PR #65 的记录显示已合并，merge commit 为 3cdfa0038afffed20540f42b03aa2484b4379b98；
- 但当前可读取的 main ref 仍为 6d23063c…；
- 当前 main 的 .github/workflows/flutter-android.yml 仍是单 job、顶层 contents: write 的版本；
- PR #65 描述的 verify/publish 两 job、权限隔离、SHA-256 sidecar 校验没有出现在本次读取到的 main 文件中；
- 对 main exact commit 查询不到成功的 Actions run；对 PR #65 head 查询到的 Flutter Android run 状态为 in_progress，没有成功结论；
- 因此当前不能把 APK、Release、provenance 或 Redmi 真机行为写成已验证。

这可能是 GitHub ref/缓存/合并同步时序问题，但在得到新的 main ref、workflow 内容和成功 run 三者一致的证据前，文档保持 UNVERIFIED/PENDING。

## 后续清理顺序

1. 以删除时的 tool/audit_remote_branches.py 输出重新确认 3 个 identical 分支。
2. 单独确认 #65 的 main ref、workflow 文件、Actions run 和 rolling release 是否一致。
3. 先处理明确 superseded 的 20 个旧分支，逐个保存 PR 号和 tip SHA，再删除。
4. 对 B2、Camera、secure-vault 分支做“代码/测试/文档提取审计”，提取后再删除。
5. 最终远程只保留 main、当前 P0 修复分支和少量真正活跃功能分支。

本审计不授权自动删除所有旧分支；任何未满足上述证据条件的分支都按 RETAIN 处理。

