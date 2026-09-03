#!/usr/bin/env bash
set -Eeuo pipefail

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tool_dir/.." && pwd)

required=(
  "$repo_root/tests/integration_test/dogfood_flow_test.dart"
  "$repo_root/tool/run_dogfood_tests.sh"
  "$repo_root/tool/validate_redmi_evidence.sh"
  "$repo_root/tool/android_mvp/redmi_dogfood_preflight.sh"
  "$repo_root/docs/REDMI_DOGFOOD_RUNBOOK.md"
  "$repo_root/docs/REDMI_DOGFOOD_EVIDENCE_TEMPLATE.json"
)

for file in "${required[@]}"; do
  [[ -f "$file" ]] || {
    echo "Missing dogfood asset: $file" >&2
    exit 1
  }
done

bash -n "$repo_root/tool/run_dogfood_tests.sh"
bash -n "$repo_root/tool/validate_redmi_evidence.sh"
bash -n "$repo_root/tool/android_mvp/redmi_dogfood_preflight.sh"

grep -Fq "process-restart surrogate" \
  "$repo_root/tests/integration_test/dogfood_flow_test.dart"
grep -Fq "不能证明操作系统杀进程后的冷启动恢复" \
  "$repo_root/docs/REDMI_DOGFOOD_RUNBOOK.md"
grep -Fq '"BLOCKED"' \
  "$repo_root/docs/REDMI_DOGFOOD_EVIDENCE_TEMPLATE.json"

echo "Dogfood assets are present, shell syntax is valid, and non-device limits are documented."
