# Redmi 真机 Dogfood Runbook

本文件不再维护第二套场景。Redmi G3 真机验收的唯一规范是：

- 执行清单：`evidence/android/REDMI_TURBO_RUNBOOK.md`
- 证据 Schema：`evidence/android/schema/evidence.schema.json`
- 阻塞模板：`evidence/android/records/synthetic.example.json`
- 校验器：`evidence/android/tool/validate_evidence.py`

当前规范使用 schema v2，并与 `tool/mvp_acceptance/audit.py` 的九场景完全一致：

`install_launch`、`offline_loop`、`process_death`、
`device_reboot`、`lock_unlock`、`permission_denied`、
`battery_restriction`、`export_delete`、`recovery_drill`。

其中 `recovery_drill` 必须验证加密备份的错误口令拒绝、密文篡改拒绝、
正确恢复、恢复后强制锁定，以及再次冷启动后的状态一致性。旧的
`RDM-001` 至 `RDM-009` 格式、双设备迁移和设备撤销场景不属于当前
Android-only MVP 的 G3 门禁，不得再用于声明 `DEVICE_VERIFIED`。

## 执行入口

先验证候选 APK、checksum 与 provenance：

```sh
python3 tool/android_mvp/verify_release_candidate.py \
  --apk personal-os-latest-debug.apk \
  --checksum personal-os-latest-debug.apk.sha256 \
  --provenance personal-os-latest-debug.provenance.json
```

完成真机记录后执行：

```sh
bash evidence/android/tool/check_evidence.sh completed-redmi-evidence.json
python3 tool/android_mvp/validate_redmi_evidence.py \
  completed-redmi-evidence.json --require-ready
```

未在目标 Redmi 上实际执行的场景只能记录为 `blocked` 或 `fail`。
Actions、模拟器、Flutter fixture 和 APK 构建不能替代真机结果。
