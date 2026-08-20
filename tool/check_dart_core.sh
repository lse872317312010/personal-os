#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CORE_ROOTS=("packages" "adapters")
readonly CONTRACT_RUNNER="test_contract/runner_dart"

cd "${REPO_ROOT}"

python3 tool/validate_local_dependencies.py

mapfile -d '' PACKAGE_FILES < <(
  find "${CORE_ROOTS[@]}" -mindepth 2 -maxdepth 2 -name pubspec.yaml -print0 | sort -z
)
if [[ -f "${CONTRACT_RUNNER}/pubspec.yaml" ]]; then
  PACKAGE_FILES+=("${CONTRACT_RUNNER}/pubspec.yaml")
fi

if ((${#PACKAGE_FILES[@]} == 0)); then
  echo "No Dart core packages found under packages/ or adapters/." >&2
  exit 1
fi

if grep -R -n -E \
  --include='pubspec.yaml' --include='*.dart' \
  'sdk:[[:space:]]*flutter|package:flutter/' "${CORE_ROOTS[@]}"; then
  echo "Flutter dependencies are not allowed in the platform-neutral Dart core." >&2
  exit 1
fi

for package_file in "${PACKAGE_FILES[@]}"; do
  package_dir="$(dirname "${package_file}")"
  echo "Resolving ${package_dir}"
  (cd "${package_dir}" && dart pub get)
done

echo "Checking Dart formatting"
dart format --output=none --set-exit-if-changed "${CORE_ROOTS[@]}"
dart format --output=none --set-exit-if-changed "${CONTRACT_RUNNER}"

for package_file in "${PACKAGE_FILES[@]}"; do
  package_dir="$(dirname "${package_file}")"
  echo "Analyzing ${package_dir}"
  (cd "${package_dir}" && dart analyze --fatal-infos --fatal-warnings)

  if [[ -d "${package_dir}/test" ]] &&
    find "${package_dir}/test" -type f -name '*_test.dart' -print -quit | grep -q .; then
    echo "Testing ${package_dir}"
    (cd "${package_dir}" && dart test)
  fi
done
