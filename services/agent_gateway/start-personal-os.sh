#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export PERSONAL_OS_OPEN_BROWSER=1
if [[ -x runtime/node ]]; then exec runtime/node server.mjs; fi
exec node server.mjs
