#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/post_export.sh"

declare -Ag JOB

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
JOB[name]="users"
EXPORT_DATE="2026-03-17"
transfer_dir="$TMP_DIR/transfer"
out_tx="$(transfer_file "$SRC_FILE" "$transfer_dir" "copy" "true" '${JOB_NAME}_${EXPORT_DATE}${EXT}')"
assert_true "[[ -f '$out_tx' ]]" "transfer output exists"

# Transfer: invalid dest (use a file path) should fail
bad_dest="$TMP_DIR/not_a_dir"
printf 'nope' >"$bad_dest"
if transfer_file "$SRC_FILE" "$bad_dest" "move" "true" ""; then
  echo "FAIL: transfer should fail when dest is a file" >&2
  exit 1
fi

echo "OK: post_export_test.sh"
