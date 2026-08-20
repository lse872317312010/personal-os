#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo 'usage: check_evidence.sh RECORD.json' >&2
  exit 64
fi
if ! command -v jq >/dev/null 2>&1; then
  echo 'EVIDENCE_CHECK=blocked TOOL_MISSING=jq'
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo 'EVIDENCE_CHECK=blocked TOOL_MISSING=python3'
  exit 2
fi

record="$1"
tool_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$tool_dir/validate_evidence.py" "$record"

jq -e '
  .schemaVersion == 1 and
  (.recordKind == "real_device" or .recordKind == "synthetic") and
  .targetClass == "redmi_turbo" and
  (.scenarios | length) == 9 and
  ([.scenarios[].id] | unique | length) == 9 and
  ([.scenarios[] | .checksPassed <= .checksTotal] | all) and
  ([.scenarios[] | if .result == "pass" then
      .checksPassed == .checksTotal and .failureCode == "none"
    else
      .failureCode != "none"
    end] | all)
' "$record" >/dev/null

echo 'EVIDENCE_CHECK=pass'
