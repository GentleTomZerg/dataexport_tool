#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/post_export.sh"

assert_true() {
  local cond="$1"
  local msg="$2"
  if ! eval "$cond"; then
    echo "FAIL: $msg" >&2
    exit 1
  fi
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC_FILE="$TMP_DIR/export.csv"
printf 'id,name\n1,Alice\n' >"$SRC_FILE"

# Compression: gz
out_gz="$(compress_file "$SRC_FILE" "gz" "true" "false")"
assert_true "[[ -f '$out_gz' ]]" "gz output exists"

# Compression: tar.gz
out_tgz="$(compress_file "$SRC_FILE" "tar.gz" "true" "false")"
assert_true "[[ -f '$out_tgz' ]]" "tar.gz output exists"

# Transfer: copy with rename
JOB_NAME="users"
EXPORT_DATE="2026-03-17"
transfer_dir="$TMP_DIR/transfer"
out_tx="$(transfer_file "$SRC_FILE" "$transfer_dir" "copy" "true" '${JOB_NAME}_${EXPORT_DATE}${EXT}')"
assert_true "[[ -f '$out_tx' ]]" "transfer output exists"

echo "OK: post_export_test.sh"
