#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 path/to/completed-redmi-evidence.json" >&2
  exit 2
fi

python3 - "$1" <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))

def require(mapping, key, label):
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"missing non-empty {label}")
    return value.strip()

if data.get("schema_version") != 1:
    raise SystemExit("schema_version must be 1")

commit = require(data, "commit_sha", "commit_sha")
if not re.fullmatch(r"[0-9a-fA-F]{40}", commit):
    raise SystemExit("commit_sha must be a 40-character SHA-1")

apk_sha = require(data, "apk_sha256", "apk_sha256")
if not re.fullmatch(r"[0-9a-fA-F]{64}", apk_sha):
    raise SystemExit("apk_sha256 must be a 64-character SHA-256")

device = data.get("device")
if not isinstance(device, dict):
    raise SystemExit("device must be an object")
for key in ("model", "android_version", "build_number"):
    require(device, key, f"device.{key}")

scenarios = data.get("scenarios")
if not isinstance(scenarios, list) or not scenarios:
    raise SystemExit("scenarios must be a non-empty array")

seen = set()
for scenario in scenarios:
    if not isinstance(scenario, dict):
        raise SystemExit("each scenario must be an object")
    scenario_id = require(scenario, "id", "scenario.id")
    if scenario_id in seen:
        raise SystemExit(f"duplicate scenario id: {scenario_id}")
    seen.add(scenario_id)
    result = require(scenario, "result", f"{scenario_id}.result").upper()
    if result not in {"PASS", "FAIL", "BLOCKED", "N/A"}:
        raise SystemExit(f"invalid result for {scenario_id}: {result}")
    require(scenario, "observed_at_utc", f"{scenario_id}.observed_at_utc")
    require(scenario, "notes", f"{scenario_id}.notes")

print(f"Validated {len(scenarios)} Redmi dogfood scenario records for {commit}.")
PY

