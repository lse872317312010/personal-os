#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 path/to/completed-redmi-evidence.json [--require-ready]" >&2
  exit 2
fi

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
python3 "$tool_dir/android_mvp/validate_redmi_evidence.py" "$@"
