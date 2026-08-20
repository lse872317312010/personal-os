#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$repo_root"

if ! command -v flutter >/dev/null 2>&1; then
  echo 'BUILD_CHECK=blocked TOOL_MISSING=flutter'
  exit 2
fi

flutter analyze
flutter test
flutter build apk --debug
echo 'BUILD_CHECK=pass PROFILE=debug'
