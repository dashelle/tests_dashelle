#!/usr/bin/env bash
set -eo pipefail
# NB: deliberately NOT using -u to avoid path expansion issues in tests

#######################################
# Paths
#######################################
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$TEST_DIR/.." && pwd)"

SCRIPT="$PROJECT_DIR/update_permissions.sh"

TEST_ROOT="/tmp/permtest"
IMPORT_FILE="$TEST_ROOT/list.txt"

#######################################
# Counters
#######################################
PASS_COUNT=0
FAIL_COUNT=0

#######################################
# Helpers
#######################################
log() {
  echo "[TEST] $*"
}

pass() {
  echo "[PASS] $*"
  PASS_COUNT=$((PASS_COUNT+1))
}

fail() {
  echo "[FAIL] $*"
  FAIL_COUNT=$((FAIL_COUNT+1))
}

assert_file_exists() {
  if [[ -e "$1" ]]; then
    pass "File exists: $1"
  else
    fail "File does not exist: $1"
  fi
}

assert_mode() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(stat -c '%a' "$file")"

  if [[ "$actual" == "$expected" ]]; then
    pass "Mode $expected on $file"
  else
    fail "Expected mode $expected on $file, got $actual"
  fi
}

assert_owner() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(stat -c '%U:%G' "$file")"

  if [[ "$actual" == "$expected" ]]; then
    pass "Owner $expected on $file"
  else
    fail "Expected owner $expected on $file, got $actual"
  fi
}

#######################################
# Cleanup
#######################################
cleanup() {
  log "Cleanup"
  [[ -n "$TEST_ROOT" ]] && rm -rf "$TEST_ROOT"
  userdel -r tuser 2>/dev/null || true
  groupdel tgroup 2>/dev/null || true
}

trap cleanup EXIT

#######################################
# Test setup
#######################################
log "Preparing test sandbox"

mkdir -p "$TEST_ROOT/dir/sub"
touch "$TEST_ROOT/a.txt"
touch "$TEST_ROOT/dir/b.conf"
touch "$TEST_ROOT/dir/sub/c.log"

cat > "$IMPORT_FILE" <<EOF
$TEST_ROOT/a.txt
$TEST_ROOT/dir
$TEST_ROOT/dir/*.conf
$TEST_ROOT/dir/sub
EOF

assert_file_exists "$SCRIPT"
assert_file_exists "$IMPORT_FILE"

#######################################
# Tests
#######################################
log "TEST 1: report only"
"$SCRIPT" --import "$IMPORT_FILE" --report >/dev/null
pass "Report works"

log "TEST 2: chmod 644"
"$SCRIPT" --import "$IMPORT_FILE" --chmod=644 >/dev/null
assert_mode "$TEST_ROOT/a.txt" "644"

log "TEST 3: chmod recursive"
"$SCRIPT" --import "$IMPORT_FILE" --chmod=700 -R >/dev/null
assert_mode "$TEST_ROOT/dir/sub/c.log" "700"

log "TEST 4: chown with create"
"$SCRIPT" --import "$IMPORT_FILE" --create --chown=tuser:tgroup >/dev/null
assert_owner "$TEST_ROOT/a.txt" "tuser:tgroup"

log "TEST 5: idempotency"
"$SCRIPT" --import "$IMPORT_FILE" --create --chown=tuser:tgroup --chmod=700 -R >/dev/null
assert_owner "$TEST_ROOT/a.txt" "tuser:tgroup"
assert_mode "$TEST_ROOT/a.txt" "700"

#######################################
# Summary
#######################################
echo
echo "=============================="
echo "TOTAL PASSED: $PASS_COUNT"
echo "TOTAL FAILED: $FAIL_COUNT"
echo "=============================="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
