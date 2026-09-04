# 远端分支收敛审计（2026-09-04）

仓库：`lse872317312010/personal-os`  
审计基线：`main@e65f2d9fb6e5440c49416f05e1dc4becf80dfcb0`

## 已验证事实

- `main` 与 `android-latest` 均指向审计基线；主线 Android run #328 成功，
  APK、SHA-256 与 provenance 已发布。
- 清理开始时共有 68 个分支（`main` + 67 个非主线分支），没有开放 PR。
- 第一批删除 9 个 tip 精确等于已合并 PR head 的分支。
- 第二批人工核验并删除 25 个被替代、过期或明确拒绝的分支。
- 删除后通过 GitHub branch search 重新枚举，共剩 34 个分支：`main` +
  下表 33 个历史分支。
- 删除分支没有触发 GitHub Actions；关闭/合并 PR 中的提交仍可恢复。

仅使用 ahead/behind 或 `git branch --merged main` 不足以审计本仓库，因为历史
PR 大量使用 squash merge。删除判断必须同时使用精确 tip、PR 替代链、逐文件
差异和当前主线安全边界。

## 剩余 33 个历史分支

下列 tip 已在 2026-09-04 重新读取。结论均为“可删除历史 ref”；这不表示把旧
实现重新合并到主线。

| 分支 | 精确 tip | 审计结论 |
|---|---|---|
| `codex/b2-02-controlled-source-entry-20260824` | `53e33db85d98e48ce78747bcf0805be827688f8f` | #39 已由合并的 #46 重提取 |
| `codex/b2-02-controlled-source-entry-v2-20260824` | `7a5246ee46a2a4d317fd44efbc9b95e5353a4b95` | #43 已由合并的 #46 重提取 |
| `codex/b2-03-ingest-appearance-20260824` | `14fe379ec5d74464d4c3c03b298b67e71e364931` | #40 已由合并的 #45 重提取 |
| `codex/b2-dart-controlled-source-port-20260824` | `1fbbccb76cfd849d15fcc9441263ee8c6bbb2a8e` | #47 已由合并的 #50 重提取 |
| `codex/b2-native-source-handoff-20260824` | `12ad2d8b8a3eca788dd0a02b51145315693e8d2a` | 原生交接已由合并的 #52 完成 |
| `codex/baseline-format-relay-20260824` | `648e3d448b8298239f187fc5fcaea8d1a9e9dcf2` | 格式修复已由合并的 #44 完成 |
| `feat/native-camera-capture` | `e0a1b70db8d50c119c5a264efc1ca16a13980875` | #62 已由合并的 #63 从新基线重建 |
| `codex/p0-android-release-evidence` | `33be661b0003a4535fa18a7b212381e7b160646e` | 旧 Flutter 3.24 workflow；当前 3.47 主线已验证发布 |
| `codex/p0-android-release-evidence-followup` | `a9b7939fe89e28239d0175d850487beef4f82ab2` | #67 的绕门禁方案已关闭；#70/#72 已建立绿色基线 |
| `feature/wave-11/I-backlog-status` | `56f56e4ced2a71b1399b18dfca4487e82272977d` | 过期路线图快照 |
| `feature/wave-11/I-ci-hardening` | `596b16369af8553bb46e87a2a65a9af6a1de19b8` | 当前 contracts/Linux/Windows/Android 门禁更完整 |
| `feature/wave-11/I-evidence-writer` | `b4a07fdf5f6ab1c9af95aca23dbbee4cc542b014` | 旧证据写入器已被 #34 的 fail-closed ledger 取代 |
| `feature/wave-11/I-fill-g0-static-evidence` | `2a2249a071008fe0bafa43584740287739e3ba9d` | 绑定旧 commit 的静态证据，已失效 |
| `feature/wave-11/I-secretscan-fp` | `39f764a01bf3c265bff95b2f1b17754e3bda0b4f` | 当前 `check_secrets.sh` 已覆盖 |
| `feature/wave-12/I-build-evidence` | `b1769a0986303856098a5f9b139ead7a33581610` | 已被 APK provenance/SHA/Release 证据链取代 |
| `feature/wave-13/D-mode-chip-tests` | `7ea4a841d243dae31ce8f0adf385b181b4f59033` | 三模式与空壳重启测试已不符合单入口安全装配 |
| `feature/wave-13/D-sqlite-composition` | `141bb8ad0ee097b45a73aa459f82b8df62501ece` | 旧 dev/prod 三入口已由 Android 默认安全 Vault 取代 |
| `feature/wave-14/D-imagepicker-manifest` | `af02a3425b1904dc072e88a689849cec573d1501` | 过度权限/FileProvider 方案已由系统 Photo Picker 边界取代 |
| `feature/wave-14/D-imagepicker-ui` | `c9bd0b83e5601ef6ef283eed3e11a5c409743633` | Dart 读取原始图片方案已由原生 token→SQLCipher Blob 取代 |
| `feature/wave-15/C-methodchannel-impl` | `3d52a2a23b05fd79746eb0917da133c8b87bf426` | 旧密钥通道会返回密文材料；当前密钥不跨 Dart |
| `feature/wave-15/C-real-sqlite-sqlcipher` | `f70a202bbaf9ef3c3dcb79496bf992c8773f3bd3` | 旧 Flutter SQLite 插件方案已由原生 SQLCipher 4.17 取代 |
| `feature/wave-16/D-export-delete-recovery-ui` | `887fee260233b87d1b83955b66b4b30f547aa54a` | 仅静态 UI，未绑定加密导出/原子删除/恢复服务 |
| `feature/wave-16/I-adr0008-grep-and-pr-template` | `7ebf96374b524302fbe46b188d7b1bb83cac9ca6` | 硬编码 grep 已由动态 composition/persistence 审计取代 |
| `feature/wave-17a_D-export-packager` | `01dc8c8e4af32b78742bacd915fd9d8f1b5ba334` | 明文 JSON + 固定 dev seed，不符合加密导出端口 |
| `feature/wave-17b_D-delete-guard` | `42171a714529d1ba70a8fec6bfb7d168f326ec0c` | 仅 UI guard，不能证明 Blob/事件/密钥原子删除 |
| `feature/wave-17c_D-recovery-verifier` | `267575c4470fc8f6a01e60516e169c2449b685fb` | 绑定旧明文 envelope；当前 RecoverySession 更严格 |
| `feature/wave-18a_C-in-memory-blob-store` | `27a8143ad7d3df8d95cefe6debb5a28ead4c62aa` | 纯内存 Blob 不进入 Android 安全路径 |
| `feature/wave-18b_B-eventstore-readall` | `d6416797ad5aca8f1543e892972f36fbe9286401` | 无界 `readAll()` 扩大导出面；当前使用受限查询与导出请求 |
| `feature/wave-18c_A-adr-0009-0010` | `1317613fd384c163146253e7c8482e039418326a` | 旧 evidence 合同已由 #34 取代；生命周期假设已变更 |
| `feature/wave-18d_T-integration-test-skeleton` | `2d48657991f7b004519f1ba22e93a173145993d2` | 空壳测试已由可执行 Redmi dogfood 流程取代 |
| `feature/wave-B/A-adr-0006-0008` | `837f269a7123a09b6f4a4d9fba8aa103e8929c90` | 含 `image_picker`、三入口及 VMK 进入 Dart 等过时/错误假设 |
| `feature/wave-B/A-backlog-sync-13prs` | `812fb3e3c459c74a65f7aa9c1c06275955b286b2` | 过期 Wave 路线图快照 |
| `feature/wave-B/A-requirements-inbox-0817` | `864eaff918f582203ac7373ce2cb849aa93eb1ca` | 保留 10 条用户意图，但实现引用过时；按当前架构重写而非合并 |

## 提取结论

- 不从旧相机、SQLCipher、导出、删除或恢复分支复制生产代码。
- 后续数据生命周期实现以当前 `EventExportPort`（只允许认证加密字节）、
  `DeletionUseCase`（现阶段仅逻辑协议）和 `RecoverySession` 为合同，从最新
  `main` 新建单一功能分支。
- `RI-MEN-001..010` 的产品意图仍有参考价值，但必须删除 `image_picker`、
  三启动入口、纯离线 fixture 等已过时实现假设后再进入需求文档。

## 下一门禁

删除上表 33 个 ref 前，执行时必须再次确认 tip 未变化、无开放 PR，并取得删除
确认。删除完成后，远端应只剩 `main`；随后开始 Redmi `RDM-001..009` 真机
验收，真机通过后再启用真实模型与建议→行动→反馈闭环。
