#!/usr/bin/env bash
# Tests for tool/check_secrets.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_SCRIPT="${SCRIPT_DIR}/../check_secrets.sh"
TMP_DIR=""

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

pass_count=0
fail_count=0

assert_pass() {
  local name="$1"
  local dir="$2"
  # Copy script to tmp dir so ROOT resolves correctly
  mkdir -p "$dir/tool"
  cp "$SECRETS_SCRIPT" "$dir/tool/check_secrets.sh"
  if (cd "$dir" && bash tool/check_secrets.sh) >/dev/null 2>&1; then
    echo "PASS: $name"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $name (expected pass but got fail)"
    fail_count=$((fail_count + 1))
  fi
}

assert_fail() {
  local name="$1"
  local dir="$2"
  mkdir -p "$dir/tool"
  cp "$SECRETS_SCRIPT" "$dir/tool/check_secrets.sh"
  if (cd "$dir" && bash tool/check_secrets.sh) >/dev/null 2>&1; then
    echo "FAIL: $name (expected fail but got pass)"
    fail_count=$((fail_count + 1))
  else
    echo "PASS: $name"
    pass_count=$((pass_count + 1))
  fi
}

# Test 1: Clean project passes
TMP_DIR=$(mktemp -d)
mkdir -p "$TMP_DIR/packages/test/lib"
echo 'void main() {}' > "$TMP_DIR/packages/test/lib/main.dart"
cat > "$TMP_DIR/packages/test/pubspec.yaml" << 'EOF'
name: test
EOF
assert_pass "clean project passes" "$TMP_DIR"
rm -rf "$TMP_DIR"

# Test 2: GitHub PAT detected
TMP_DIR=$(mktemp -d)
mkdir -p "$TMP_DIR/packages/test/lib"
echo 'const token = "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";' > "$TMP_DIR/packages/test/lib/main.dart"
cat > "$TMP_DIR/packages/test/pubspec.yaml" << 'EOF'
name: test
EOF
assert_fail "GitHub PAT detected" "$TMP_DIR"
rm -rf "$TMP_DIR"

# Test 3: AWS access key detected
TMP_DIR=$(mktemp -d)
mkdir -p "$TMP_DIR/packages/test/lib"
echo 'const key = "AKIAIOSFODNN7EXAMPLE";' > "$TMP_DIR/packages/test/lib/main.dart"
cat > "$TMP_DIR/packages/test/pubspec.yaml" << 'EOF'
name: test
EOF
assert_fail "AWS access key detected" "$TMP_DIR"
rm -rf "$TMP_DIR"

# Test 4: Hardcoded password detected
TMP_DIR=$(mktemp -d)
mkdir -p "$TMP_DIR/packages/test/lib"
echo 'const password = "super_secret_password123";' > "$TMP_DIR/packages/test/lib/main.dart"
cat > "$TMP_DIR/packages/test/pubspec.yaml" << 'EOF'
name: test
EOF
assert_fail "hardcoded password detected" "$TMP_DIR"
rm -rf "$TMP_DIR"

# Test 5: Test fixtures directory excluded
TMP_DIR=$(mktemp -d)
mkdir -p "$TMP_DIR/packages/test/fixtures"
echo 'const token = "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";' > "$TMP_DIR/packages/test/fixtures/data.dart"
cat > "$TMP_DIR/packages/test/pubspec.yaml" << 'EOF'
name: test
EOF
assert_pass "fixtures directory excluded" "$TMP_DIR"
rm -rf "$TMP_DIR"

echo ""
echo "Results: $pass_count passed, $fail_count failed"
if [[ $fail_count -gt 0 ]]; then
  exit 1
fi
