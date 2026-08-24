# MVP 可用性验收门

状态：M3 进入前的执行基线

## 目的

本门禁回答的是“这个应用现在能否交给首位用户在 Redmi Turbo 上真实使用”，而不是“仓库里是否已有相关代码”。所有结论由 `evidence/mvp/status.json` 的可复核证据产生；代码数量、设计文档、fake adapter、synthetic fixture 和测试计划均不能替代运行证据。

执行：

```bash
python3 tool/mvp_acceptance/audit.py
python3 -m unittest discover -s tool/mvp_acceptance/tests -v
```

审计器只使用 Python 标准库，不访问网络、不修改设备、不读取用户内容。默认读取仓库根目录下的 `evidence/mvp/status.json`，以非零退出码表示目标 gate 未通过或证据无效。

## 五级 gate

| Gate | 准确含义 | 最低证据 | 不能声称 |
|---|---|---|---|
| G0 `static` | 仓库静态契约与依赖审计通过 | 命令、时间、提交、成功退出码 | Flutter 可运行、应用可用 |
| G1 `flutter_test` | 指定提交上的 analyze/unit/widget/integration tests 通过 | 每个必需 suite 的命令、时间、提交、成功退出码 | 已生成 APK、真机通过 |
| G2 `apk` | 可安装 Android APK 已在指定提交可复现构建 | 构建命令、产物 SHA-256、大小、时间、提交 | 已安装或在 Redmi 上可用 |
| G3 `redmi_device` | APK 在 Redmi Turbo 上完成安装和九场景真机 runbook | 设备类别与 OS 大版本、APK digest、逐场景 pass 记录、执行人确认；不得记录设备唯一标识 | 真实数据闭环有效、长期可用 |
| G4 `dogfood` | 用户用真实（非 fixture）数据完成至少一个有限周期 | 周期起止、闭环节点、反馈引发修订、隐私/负担评价和用户签字确认；仅存去敏元数据 | 产品长期价值已证明、所有领域可用 |

Gate 严格递进；高一级不能掩盖低一级失败。只有 G0–G4 全部通过，审计器才输出 `DOGFOOD_READY`。G0–G2 全过只能称 `BUILD_VERIFIED`；G3 通过只能称 `DEVICE_VERIFIED`。

## 必须闭环

真实 dogfood 证据必须覆盖同一个 `cycle_id` 的以下节点，且顺序与语义可追溯：

1. `baseline`：带时间、来源、质量和确认状态的外形基线；
2. `goal`：成功条件、周期、预算/偏好/健康约束；
3. `opportunity`：至少一个机会可追溯至目标与基线差距；
4. `plan_approved`：有限周期计划经用户批准，任务有完成及停止条件；
5. `execution`：至少一条真实完成，并允许且如实保存跳过、困难或不良反应；
6. `feedback`：用户对执行或结果提供真实反馈；
7. `revision`：反馈实际改变 Claim 或 Plan，保存前后版本与理由；
8. `review`：比较基线、目标、执行、结果和混杂因素，结论属于有效/无效/不确定/执行不足之一；
9. `user_value_confirmation`：用户确认复盘价值或行动清晰度是否高于一次性对话，并评价记录负担、隐私风险与建议错误。

另外必须证明：D4 未持久化；D3 同意可撤销；R3 仍只生成草案；导出/删除范围可解释；冷启动/离线重启后状态一致。真实照片、正文、密钥、设备 ID 和账户 ID 不进入本目录，只记录去敏的检查结果和 digest。

## Redmi Turbo 九场景

G3 必须逐项通过 `evidence/android/REDMI_TURBO_RUNBOOK.md` 对应的九个场景：`install_launch`、`offline_loop`、`process_death`、`device_reboot`、`lock_unlock`、`permission_denied`、`battery_restriction`、`export_delete`、`recovery_drill`。审计只接受完整集合，不接受总括性的“真机测试通过”。

## 证据规则

- `kind: synthetic` 永远不能令 gate 通过；示例状态文件故意保持所有 gate 未通过。
- 每个通过项必须包含 RFC 3339 UTC 时间、40 位 Git commit、执行命令或受控人工步骤、检查者和结果；子检查自身的 `commit` 也必须等于候选提交，不能只依赖 gate 外层字段；构建产物还需 SHA-256。
- 所有子检查必须显式列出。缺失、`skip`、`planned`、`blocked` 均为未通过；不得用百分比折算。
- commit 不一致时不得组合成同一次候选发布，除非重新执行旧证据并指向同一候选提交。
- Android 记录必须包含 `candidateCommit`；`overall: pass` 只允许出现在 `recordKind: real_device` 且九个场景全部通过的记录中。synthetic 记录永远不能通过 Android 整体校验。
- 证据只声明观察到的事实。没有 Flutter SDK 就写 `blocked`；没有 APK 就写 `blocked`；没有接入真机就写 `not_run`。
- 真实 dogfood 周期必须为 2–6 周；短期开发演示不能算完整周期。
- 任何证据不得包含用户外貌正文、照片路径、日志原文、设备序列号或密钥材料。审计器会拒绝已知敏感字段名，但人工评审仍是发布前必需项。

## 发布结论

- `NOT_VERIFIED`：G0 未过。
- `STATIC_VERIFIED`：仅 G0 通过。
- `TEST_VERIFIED`：G0–G1 通过。
- `BUILD_VERIFIED`：G0–G2 通过。
- `DEVICE_VERIFIED`：G0–G3 通过，可以发给用户做受控 dogfood，但不能宣称 MVP 已验证。
- `DOGFOOD_READY`：G0–G4 通过，且完整闭环、安全断言和用户价值确认均存在。

发布说明必须原样引用审计结论及候选 commit。任何更强措辞都需要新的证据记录，而不是修改文案。
