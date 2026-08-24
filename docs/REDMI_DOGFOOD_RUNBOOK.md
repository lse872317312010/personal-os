# Redmi 真机 Dogfood Runbook

这份 runbook 是一个可审计的执行清单，不是“已通过”声明。它把 Flutter/fixture 测试、APK 安装预检和 Redmi 真机结果分开记录。没有实际在目标手机上完成并记录的步骤，必须写成 `BLOCKED`、`FAIL` 或 `N/A`，不能用桌面测试、合成 fixture 或 Actions 结果代替。

## 1. 验收边界

目标纵向流程：

```text
首次启动 → Vault 锁定门 → 系统认证解锁 → Photo Picker
→ native 安全 Blob → 分析 → observation history
→ force-stop/重启恢复 → Vault 锁定后不泄露受保护状态
```

失败路径必须单独记录：取消选择、系统权限拒绝（若该路径出现）、Vault 锁定/会话失效、source 过期或不可用、分析失败后的 Blob 清理。

当前非真机测试使用 `InMemoryEventStore` 和 synthetic model fixture，只验证 Dart/UI 编排、opaque token 边界、回滚和状态恢复替身；它们**不是** Android Keystore、SQLCipher、Photo Picker 或真实模型的证据。特别是“process-restart surrogate”只能证明 controller 重建逻辑，不能证明操作系统杀进程后的冷启动恢复。

## 2. 先执行非真机测试

在仓库根目录执行：

```sh
bash tool/verify_dogfood_assets.sh
bash tool/run_dogfood_tests.sh
```

测试覆盖：

- 首次 UI 启动必须先经过 Vault gate；
- 合成体验中的观察记录和锁定清理；
- 受控 source token → BlobRef → analysis → observation history；
- controller 重建后的 history projection；
- 取消和 denied 失败路径；
- 锁定或未授权时不调用 source boundary；
- analysis 失败时回滚新 BlobRef。

## 3. 获取 APK 与记录候选版本

从 GitHub Release 下载候选 APK，并记录：

```sh
sha256sum personal-os-latest-debug.apk
git rev-parse HEAD
```

Release、APK SHA-256 和 provenance 中的 commit 必须指向同一个候选 commit。若不一致，停止验收。

## 4. Redmi 预检

开启开发者选项和 USB 调试，确认手机已授权。脚本只收集型号、Android 版本、系统 build、APK SHA-256 和候选 commit；不收集 serial、logcat、截图或用户内容：

```sh
bash tool/android_mvp/redmi_dogfood_preflight.sh \
  /path/to/personal-os-latest-debug.apk \
  /path/to/redmi-dogfood-preflight.json
```

预检的 `PASS` 只表示安装和启动命令成功，不能被解释为应用流程通过。

## 5. 手工场景与证据规则

将 `docs/REDMI_DOGFOOD_EVIDENCE_TEMPLATE.json` 复制为本次证据文件，逐项填写。每个场景填写 UTC 时间、结果、可复现操作、观察到的 UI/稳定错误码和限制。

| ID | 场景 | 通过条件 |
|---|---|---|
| RDM-001 | 首次启动 | 首屏显示 Vault gate；未解锁时不显示历史、Blob 或分析结果 |
| RDM-002 | Vault 解锁 | 仅经系统认证进入；认证取消/拒绝时保持锁定并显示稳定错误码 |
| RDM-003 | Photo Picker 选择 | 选择后 Dart 只看到 opaque token；UI 不显示 URI、路径或 provider 信息 |
| RDM-004 | 取消选择 | 返回/取消后无 Blob、无 observation、无模型调用泄漏 |
| RDM-005 | 权限拒绝 | 若系统出现权限提示，拒绝后保持 fail-closed；若 Photo Picker 无运行时权限提示，记为 `N/A` 并说明原因，不伪造拒绝结果 |
| RDM-006 | Blob 与分析 | native source 写入安全 Blob，应用只得到 BlobRef；分析成功或稳定失败，均无原始路径/字节进入 UI、事件或日志 |
| RDM-007 | Observation history | 成功记录后显示 metadata；不显示 BlobRef、URI、路径或原始照片内容引用 |
| RDM-008 | force-stop/重启 | `adb shell am force-stop com.personalos.app` 后重新启动；解锁后 history 与之前一致，未解锁时历史隐藏 |
| RDM-009 | Vault 锁定 | 手动锁定/会话失效后清掉内存中的受保护 projection，返回 Vault gate；重新解锁后从持久层恢复 |

建议的重启操作：

```sh
adb shell am force-stop com.personalos.app
adb shell monkey -p com.personalos.app -c android.intent.category.LAUNCHER 1
```

不要用 `adb logcat` 中的内部路径、URI、密钥别名或用户照片作为证据上传。证据只保留必要的脱敏错误码、截图引用和命令结果。

## 6. 结果解释

- `PASS`：在目标 Redmi 上实际观察到通过条件，并记录候选 commit/APK digest。
- `FAIL`：实际执行且不满足通过条件；记录最小复现和脱敏错误。
- `BLOCKED`：前置能力缺失，例如 APK 未构建、secure model adapter 尚不可用、设备未连接。
- `N/A`：该场景在目标系统没有对应路径，例如 Photo Picker 没有运行时权限对话框；必须写明理由。

任何真机场景显示 `BLOCKED` 或 `FAIL`，整体不能标记为 `DOGFOOD_READY`。本 runbook 不会把 synthetic 测试结果提升为真机结论。
