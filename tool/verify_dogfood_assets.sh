#!/usr/bin/env bash
set -Eeuo pipefail

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tool_dir/.." && pwd)

required=(
  "$repo_root/tests/integration_test/dogfood_flow_test.dart"
  "$repo_root/tool/run_dogfood_tests.sh"
  "$repo_root/tool/validate_redmi_evidence.sh"
  "$repo_root/tool/android_mvp/redmi_dogfood_preflight.sh"
  "$repo_root/tool/android_mvp/verify_release_candidate.py"
  "$repo_root/tool/android_mvp/validate_redmi_evidence.py"
  "$repo_root/docs/REDMI_DOGFOOD_RUNBOOK.md"
  "$repo_root/docs/REDMI_DOGFOOD_EVIDENCE_TEMPLATE.json"
  "$repo_root/evidence/android/REDMI_TURBO_RUNBOOK.md"
  "$repo_root/evidence/android/schema/evidence.schema.json"
  "$repo_root/evidence/android/tool/validate_evidence.py"
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
python3 -m unittest discover -s "$repo_root/tool/android_mvp" -p 'test_*redmi_evidence.py'
python3 -m unittest discover -s "$repo_root/tool/android_mvp" -p 'test_*release_candidate.py'
if python3 "$repo_root/tool/android_mvp/validate_redmi_evidence.py" \
  "$repo_root/docs/REDMI_DOGFOOD_EVIDENCE_TEMPLATE.json" >/dev/null 2>&1; then
  echo "Unchanged evidence template must not validate." >&2
  exit 1
fi

grep -Fq "process-restart surrogate" \
  "$repo_root/tests/integration_test/dogfood_flow_test.dart"
grep -Fq "evidence/android/REDMI_TURBO_RUNBOOK.md" \
  "$repo_root/docs/REDMI_DOGFOOD_RUNBOOK.md"
grep -Fq "不能替代真机结果" \
  "$repo_root/docs/REDMI_DOGFOOD_RUNBOOK.md"
grep -Fq '"schemaVersion": 2' \
  "$repo_root/docs/REDMI_DOGFOOD_EVIDENCE_TEMPLATE.json"
grep -Fq '"result": "blocked"' \
  "$repo_root/docs/REDMI_DOGFOOD_EVIDENCE_TEMPLATE.json"

echo "Dogfood assets are present, shell syntax is valid, and non-device limits are documented."
