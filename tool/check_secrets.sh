#!/usr/bin/env bash
set -Eeuo pipefail

# Secret scan for the Dart core and adapters.
# Checks for common hardcoded credential patterns that should never be
# committed. Conservative scan focused on obvious leaks, not a replacement
# for dedicated tools like gitleaks.

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SCAN_ROOTS=("packages" "adapters" "apps" "test_contract")

cd "${REPO_ROOT}"

echo "Running secret scan..."

# Patterns for hardcoded secrets. Intentionally conservative to avoid
# false positives on test fixtures and documentation.
PATTERNS=(
  'gh[pousr]_[A-Za-z0-9]{36,}'
  'AKIA[0-9A-Z]{16}'
  'BEGIN[[:space:]]+(RSA[[:space:]]+|EC[[:space:]]+|DSA[[:space:]]+|OPENSSH[[:space:]]+)?PRIVATE[[:space:]]+KEY'
  '(password|passwd|pwd)[[:space:]]*[:=][[:space:]]*["'\''][^"'\'']{8,}["'\'']'
  '(api[_-]?key|api[_-]?token|secret[_-]?key|access[_-]?token)[[:space:]]*[:=][[:space:]]*["'\''][A-Za-z0-9_-]{20,}["'\'']'
)

FOUND=0
for root in "${SCAN_ROOTS[@]}"; do
  if [[ ! -d "$root" ]]; then
    continue
  fi
  for pattern in "${PATTERNS[@]}"; do
    if grep -R -n -E --include='*.dart' --include='*.yaml' --include='*.yml' \
        --include='*.sh' --include='*.py' --include='*.json' \
        --exclude-dir='.dart_tool' --exclude-dir='build' \
        --exclude='*.lock' --exclude-dir='fixtures' \
        "$pattern" "$root" 2>/dev/null; then
      echo "  WARNING: potential secret in $root" >&2
      FOUND=1
    fi
  done
done

if [[ $FOUND -eq 1 ]]; then
  echo "Secret scan FAILED: potential hardcoded secrets found." >&2
  echo "If false positive (test placeholder), add exclusion or move to fixtures/." >&2
  exit 1
fi

echo "Secret scan passed: no hardcoded secrets detected."
