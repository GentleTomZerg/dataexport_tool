#!/usr/bin/env bash
set -euo pipefail

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"

  if [[ "$expected" != "$actual" ]]; then
    echo "ASSERT FAIL: expected='$expected' actual='$actual' $msg" >&2
    return 1
  fi
}

assert_file_exists() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "ASSERT FAIL: missing file $file" >&2
    return 1
  fi
}

tempdir() {
  mktemp -d 2>/dev/null || mktemp -d -t tmp
}
