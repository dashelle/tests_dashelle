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
  actual="$(stat -c '%U:%G' "$file
