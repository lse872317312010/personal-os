#!/usr/bin/env bash
set -euo pipefail

# Read-only readiness probe. Suppress all ADB output because it may contain a
# device serial or environment-specific diagnostics. This script neither opens
# a shell nor reads properties, logs, files, package lists, or app data.
if ! command -v adb >/dev/null 2>&1; then
  echo 'ADB_READY=fail TOOL_MISSING=adb'
  exit 1
fi

adb start-server >/dev/null 2>&1 || {
  echo 'ADB_READY=fail SERVER_UNAVAILABLE=true'
  exit 1
}

state=''
if state="$(adb get-state 2>/dev/null)" && [[ "$state" == 'device' ]]; then
  echo 'ADB_READY=pass'
  exit 0
fi

echo 'ADB_READY=fail DEVICE_READY=false'
exit 1
