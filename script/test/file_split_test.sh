#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/config/properties.sh"
source "$ROOT_DIR/lib/exportctl/model/plan.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

base_props() {
  cat <<'EOF'
job.users.DB_TYPE=mysql
job.users.DB_HOST=localhost
job.users.DB_PORT=3306
job.users.DB_NAME=demo
job.users.DB_USER=demo_user
job.users.DB_PASSWORD_FILE=/tmp/demo.pwd
job.users.DB_PASSWORD_KEY_FILE=/tmp/demo.key
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name
job.users.WHERE=id > 0
EOF
}

write_props() {
  local file="$1"
  shift
  {
    base_props
    printf '%s\n' "$@"
  } >"$file"
}

build_plan() {
  local props_file="$1"
  local plan_name="$2"
  local -A local_props=()
  load_props_from_file "$props_file" local_props
  build_export_plan local_props users "$plan_name"
}

# --- size parsing -----------------------------------------------------------

assert_eq "512" "$(parse_size_to_bytes 512)" "plain bytes"
assert_eq "1024" "$(parse_size_to_bytes 1K)" "kilobytes use 1024 base"
assert_eq "2097152" "$(parse_size_to_bytes 2M)" "megabytes use 1024 base"
assert_eq "2147483648" "$(parse_size_to_bytes 2G)" "gigabytes use 1024 base"
assert_eq "2147483648" "$(parse_size_to_bytes 2g)" "lowercase suffix accepted"

if parse_size_to_bytes 2X >/dev/null 2>&1; then
  echo "FAIL: invalid size suffix should be rejected" >&2
  exit 1
fi

# --- disabled: unchanged behaviour -----------------------------------------

write_props "$TMP_DIR/disabled.properties" \
  'job.users.EXPORT_FILE=${ENV_ROOT}/users_${EXPORT_DATE}.csv'

declare -A DISABLED=()
build_plan "$TMP_DIR/disabled.properties" DISABLED
assert_eq "false" "${DISABLED[file_split_enabled]}" "file split defaults to disabled"
assert_eq "2" "${DISABLED[file_split_index_width]}" "index width defaults to 2"
assert_eq "" "${DISABLED[file_split_max_size]}" "max size has no default"

# --- enabled: fields carried into plan, coexists with column split ----------

write_props "$TMP_DIR/valid.properties" \
  'job.users.EXPORT_FILE=${ENV_ROOT}/users_${PART}_${EXPORT_DATE}.csv' \
  'job.users.FILE_SPLIT.ENABLED=true' \
  'job.users.FILE_SPLIT.MAX_SIZE=2G' \
  'job.users.FILE_SPLIT.INDEX_WIDTH=3' \
  'job.users.COMPRESS.ENABLED=true' \
  'job.users.COMPRESS.MODE=gz' \
  'job.users.SPLIT.name=3,2'

declare -A VALID=()
build_plan "$TMP_DIR/valid.properties" VALID
assert_eq "true" "${VALID[file_split_enabled]}" "split enabled flag in plan"
assert_eq "2G" "${VALID[file_split_max_size]}" "split max size in plan"
assert_eq "3" "${VALID[file_split_index_width]}" "split index width in plan"
assert_contains '${PART}' "${VALID[export_file]}" "export template keeps PART token"
assert_eq "name|3|2" "${VALID[splits]}" "file split coexists with column split"

# --- enabled: validation failures -------------------------------------------

expect_plan_error() {
  local label="$1"
  local props_file="$2"
  local needle="$3"
  local -A PLAN=()
  local err

  if err="$(build_plan "$props_file" PLAN 2>&1 >/dev/null)"; then
    printf 'FAIL: %s: expected failure\n' "$label" >&2
    exit 1
  fi
  assert_contains "$needle" "$err" "$label"
  assert_contains "job users" "$err" "$label includes job name"
}

write_props "$TMP_DIR/missing_part.properties" \
  'job.users.EXPORT_FILE=${ENV_ROOT}/users_${EXPORT_DATE}.csv' \
  'job.users.FILE_SPLIT.ENABLED=true' \
  'job.users.FILE_SPLIT.MAX_SIZE=2G' \
  'job.users.COMPRESS.ENABLED=true' \
  'job.users.COMPRESS.MODE=gz'
expect_plan_error "EXPORT_FILE without PART" "$TMP_DIR/missing_part.properties" "EXPORT_FILE"

write_props "$TMP_DIR/bad_compress.properties" \
  'job.users.EXPORT_FILE=${ENV_ROOT}/users_${PART}.csv' \
  'job.users.FILE_SPLIT.ENABLED=true' \
  'job.users.FILE_SPLIT.MAX_SIZE=2G' \
  'job.users.COMPRESS.ENABLED=true' \
  'job.users.COMPRESS.MODE=tar.gz'
expect_plan_error "compression not gz" "$TMP_DIR/bad_compress.properties" "COMPRESS"

write_props "$TMP_DIR/bad_transfer.properties" \
  'job.users.EXPORT_FILE=${ENV_ROOT}/users_${PART}.csv' \
  'job.users.FILE_SPLIT.ENABLED=true' \
  'job.users.FILE_SPLIT.MAX_SIZE=2G' \
  'job.users.COMPRESS.ENABLED=true' \
  'job.users.COMPRESS.MODE=gz' \
  'job.users.TRANSFER.ENABLED=true' \
  'job.users.TRANSFER.DIR=/tmp/out' \
  'job.users.TRANSFER.RENAME=users_${EXPORT_DATE}.gz'
expect_plan_error "transfer rename without PART" "$TMP_DIR/bad_transfer.properties" "TRANSFER.RENAME"

write_props "$TMP_DIR/bad_size.properties" \
  'job.users.EXPORT_FILE=${ENV_ROOT}/users_${PART}.csv' \
  'job.users.FILE_SPLIT.ENABLED=true' \
  'job.users.FILE_SPLIT.MAX_SIZE=2X' \
  'job.users.COMPRESS.ENABLED=true' \
  'job.users.COMPRESS.MODE=gz'
expect_plan_error "unparseable max size" "$TMP_DIR/bad_size.properties" "MAX_SIZE"

write_props "$TMP_DIR/bad_width.properties" \
  'job.users.EXPORT_FILE=${ENV_ROOT}/users_${PART}.csv' \
  'job.users.FILE_SPLIT.ENABLED=true' \
  'job.users.FILE_SPLIT.MAX_SIZE=2G' \
  'job.users.FILE_SPLIT.INDEX_WIDTH=abc' \
  'job.users.COMPRESS.ENABLED=true' \
  'job.users.COMPRESS.MODE=gz'
expect_plan_error "non-numeric index width" "$TMP_DIR/bad_width.properties" "INDEX_WIDTH"

write_props "$TMP_DIR/zero_width.properties" \
  'job.users.EXPORT_FILE=${ENV_ROOT}/users_${PART}.csv' \
  'job.users.FILE_SPLIT.ENABLED=true' \
  'job.users.FILE_SPLIT.MAX_SIZE=2G' \
  'job.users.FILE_SPLIT.INDEX_WIDTH=0' \
  'job.users.COMPRESS.ENABLED=true' \
  'job.users.COMPRESS.MODE=gz'
expect_plan_error "zero index width" "$TMP_DIR/zero_width.properties" "INDEX_WIDTH"

echo "OK: file_split_test.sh"
