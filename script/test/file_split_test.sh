#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/config/properties.sh"
source "$ROOT_DIR/lib/exportctl/model/plan.sh"
source "$ROOT_DIR/lib/exportctl/run/artifact.sh"

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

# --- ${PART} rendering ------------------------------------------------------

expect_render_error() {
  local label="$1"
  local needle="$2"
  shift 2
  local err

  if err="$("$@" 2>&1 >/dev/null)"; then
    printf 'FAIL: %s: expected failure\n' "$label" >&2
    exit 1
  fi
  assert_contains "$needle" "$err" "$label"
}

assert_eq "00" "$(format_part_index 0 2)" "index 0 pads to 00"
assert_eq "05" "$(format_part_index 5 2)" "index 5 pads to 05"
assert_eq "99" "$(format_part_index 99 2)" "index 99 pads to 99"
assert_eq "005" "$(format_part_index 5 3)" "index width 3 pads to 005"

expect_render_error "index 100 overflows width 2" "INDEX_WIDTH" format_part_index 100 2
expect_render_error "width 0 is rejected" "INDEX_WIDTH" format_part_index 0 0

assert_eq "00-users-2026-03-17.gz" \
  "$(_render_artifact_name '${PART}-users-${EXPORT_DATE}.gz' users.csv users 2026-03-17 0 2)" \
  "transfer template renders part 00"
assert_eq "01-users-2026-03-17.gz" \
  "$(_render_artifact_name '${PART}-users-${EXPORT_DATE}.gz' users.csv users 2026-03-17 1 2)" \
  "transfer template renders part 01"
assert_eq "99-users-2026-03-17.gz" \
  "$(_render_artifact_name '${PART}-users-${EXPORT_DATE}.gz' users.csv users 2026-03-17 99 2)" \
  "transfer template renders part 99"
assert_eq "users-2026-03-17.csv" \
  "$(_render_artifact_name 'users-${EXPORT_DATE}.csv' ./exports/users.csv users 2026-03-17)" \
  "template without PART keeps existing behaviour"
assert_eq '/tmp/exports/${PART}-users.csv' \
  "$(_render_artifact_name '/tmp/exports/${PART}-users.csv' users.csv users 2026-03-17)" \
  "PART is left literal when no part index is given"

assert_eq "/tmp/exports/01-users-2026-03-17.csv" \
  "$(render_export_part_name '/tmp/exports/${PART}-users-${EXPORT_DATE}.csv' 1 2 users 2026-03-17)" \
  "export template renders the same PART placeholders as transfer"
assert_eq "/tmp/exports/01-users-2026-03-17.csv" \
  "$(render_export_part_name '/tmp/exports/${PART}-${JOB_NAME}-${EXPORT_DATE}.csv' 1 2 users 2026-03-17)" \
  "export template renders JOB_NAME like transfer"
expect_render_error "export render overflows width 2" "INDEX_WIDTH" \
  render_export_part_name '/tmp/exports/${PART}-users.csv' 100 2 users 2026-03-17

mkdir -p "$TMP_DIR/part_src" "$TMP_DIR/part_dest"
printf 'id,name\n' >"$TMP_DIR/part_src/rows.csv"
transferred="$(
  _transfer_artifact "$TMP_DIR/part_src/rows.csv" "$TMP_DIR/part_dest" copy true \
    '${PART}-users-${EXPORT_DATE}.csv' users 2026-03-17 3 2
)"
assert_eq "$TMP_DIR/part_dest/03-users-2026-03-17.csv" "$transferred" "transfer renders PART in the rename target"
assert_true "[[ -f '$TMP_DIR/part_dest/03-users-2026-03-17.csv' ]]" "renamed part file exists"
expect_render_error "transfer render overflows width 2" "INDEX_WIDTH" \
  _transfer_artifact "$TMP_DIR/part_src/rows.csv" "$TMP_DIR/part_dest" copy true \
  '${PART}-users.csv' users 2026-03-17 100 2

echo "OK: file_split_test.sh"
