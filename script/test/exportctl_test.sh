#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$ROOT_DIR/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"

cd "$PROJECT_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

rm -rf "$PROJECT_DIR/exports" "$PROJECT_DIR/exports_transfer"

mkdir -p "$TMP_DIR/pwd" "$TMP_DIR/bin"
printf 'key' >"$TMP_DIR/key"
echo -n "testpassword" | openssl des3 -salt -in /dev/stdin -out "$TMP_DIR/pwd/localhost_3306_demo_user.pwd" -pass file:"$TMP_DIR/key" -pbkdf2 -iter 100000

cat >"$TMP_DIR/bin/mysql" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '1\tAlice|!A|!\n2\tNULL\n'
EOF
chmod +x "$TMP_DIR/bin/mysql"

cat >"$TMP_DIR/env.properties" <<EOF
ENV_EXPORT_ROOT=./exports
ENV_TRANSFER_ROOT=./exports_transfer
ENV_TEST_DB_HOST=localhost
ENV_TEST_DB_PORT=3306
ENV_TEST_DB_NAME=demo
ENV_TEST_DB_USER=demo_user
ENV_TEST_DB_TYPE=mysql
ENV_TEST_DB_PASSWORD_FILE=$TMP_DIR/pwd/localhost_3306_demo_user.pwd
ENV_TEST_DB_PASSWORD_KEY_FILE=$TMP_DIR/key
EOF

cat >"$TMP_DIR/jobs.properties" <<'EOF'
job.users.DB_TYPE=${ENV_TEST_DB_TYPE}
job.users.DB_HOST=${ENV_TEST_DB_HOST}
job.users.DB_PORT=${ENV_TEST_DB_PORT}
job.users.DB_NAME=${ENV_TEST_DB_NAME}
job.users.DB_USER=${ENV_TEST_DB_USER}
job.users.DB_PASSWORD_FILE=${ENV_TEST_DB_PASSWORD_FILE}
job.users.DB_PASSWORD_KEY_FILE=${ENV_TEST_DB_PASSWORD_KEY_FILE}
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name
job.users.EXPORT_FILE=${ENV_EXPORT_ROOT}/users_${EXPORT_DATE}.csv
job.users.FIELD_SEPARATOR_DATA_REPLACEMENT=|X
job.users.WHERE=status = 'active'
job.users.COMPRESS.ENABLED=true
job.users.COMPRESS.MODE=gz
job.users.COMPRESS.OVERWRITE=true
job.users.TRANSFER.ENABLED=true
job.users.TRANSFER.DIR=${ENV_TRANSFER_ROOT}
job.users.TRANSFER.MODE=copy
job.users.TRANSFER.OVERWRITE=true
job.users.TRANSFER.RENAME=users_${EXPORT_DATE}.gz
job.default.DB_TYPE=${ENV_TEST_DB_TYPE}
job.default.DB_HOST=${ENV_TEST_DB_HOST}
job.default.DB_PORT=${ENV_TEST_DB_PORT}
job.default.DB_NAME=${ENV_TEST_DB_NAME}
job.default.DB_USER=${ENV_TEST_DB_USER}
job.default.DB_PASSWORD_FILE=${ENV_TEST_DB_PASSWORD_FILE}
job.default.DB_PASSWORD_KEY_FILE=${ENV_TEST_DB_PASSWORD_KEY_FILE}
job.default.TABLE_NAME=users
job.default.COLUMNS=id,name
job.default.EXPORT_FILE=${ENV_EXPORT_ROOT}/default_${EXPORT_DATE}.csv
job.bad.DB_TYPE=mysql
job.bad.DB_HOST=localhost
job.bad.DB_PORT=3306
job.bad.DB_NAME=demo
job.bad.DB_USER=demo_user
job.bad.DB_PASSWORD_FILE=
job.bad.DB_PASSWORD_KEY_FILE=$TMP_DIR/key
job.bad.TABLE_NAME=bad
job.bad.COLUMNS=id
job.bad.EXPORT_FILE=${ENV_EXPORT_ROOT}/bad.csv
EOF

plan_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" plan --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 2>&1)"
assert_contains "== Job: users ==" "$plan_output" "plan includes users"
assert_contains "== Job: bad ==" "$plan_output" "failed job header printed"
assert_contains "[bad] Plan build failed." "$plan_output" "bad job logged"
assert_contains "Summary: total=3 ok=2 failed=1" "$plan_output" "summary counts"
assert_contains "== Environment ==" "$plan_output" "environment block printed"
assert_contains "ENV_EXPORT_ROOT=./exports" "$plan_output" "export env printed"
assert_contains "SQL=SELECT id,name FROM users WHERE status = 'active'" "$plan_output" "plan prints sql"
assert_contains "[users] Plan generated." "$plan_output" "plan success note"

validate_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" validate --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 2>&1)"
assert_contains "== Job: users ==" "$validate_output" "validate includes users"
assert_contains "[bad] Plan build failed." "$validate_output" "validate prints failed job"
assert_contains "[users] Validation succeeded." "$validate_output" "validate success note"
assert_true "[[ \"$validate_output\" != *\"SQL=\"* ]]" "validate should not print sql"

unknown_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" plan --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 users missing_job 2>&1)"
assert_contains "ERROR: unknown job missing_job" "$unknown_output" "unknown job logged"

run_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" run --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 users 2>&1)"
assert_contains "[users] Starting export: db_type=mysql file=./exports/users_2026-03-17.csv" "$run_output" "export start log"
assert_contains "[users] Export finished: file=./exports/users_2026-03-17.csv lines=2" "$run_output" "export metrics log"
assert_contains "[users] Compressing artifact: file=./exports/users_2026-03-17.csv mode=gz" "$run_output" "compress start log"
assert_contains "[users] Compression finished: src=./exports/users_2026-03-17.csv dest=./exports/users_2026-03-17.csv.gz mode=gz remove_original=false" "$run_output" "compress ok log"
assert_contains "[users] Transferring artifact: file=./exports/users_2026-03-17.csv.gz dir=./exports_transfer mode=copy" "$run_output" "transfer start log"
assert_contains "[users] Transfer finished: src=./exports/users_2026-03-17.csv.gz dest=./exports_transfer/users_2026-03-17.gz mode=copy" "$run_output" "transfer ok log"
assert_contains "[users] Final artifact ready: file=./exports_transfer/users_2026-03-17.gz" "$run_output" "final artifact log"
assert_contains "[users] Completed successfully." "$run_output" "run success log"
assert_true "[[ -f '$PROJECT_DIR/exports/users_2026-03-17.csv' ]]" "export file created"
export_content="$(cat "$PROJECT_DIR/exports/users_2026-03-17.csv")"
assert_contains $'1\tAlice|XA|X\n2\t' "$export_content" "sanitizes |! and NULL with configured replacement"
assert_true "[[ -f '$PROJECT_DIR/exports/users_2026-03-17.csv.gz' ]]" "compressed file created"
assert_true "[[ -f '$PROJECT_DIR/exports_transfer/users_2026-03-17.gz' ]]" "transferred file created"
transfer_content="$(gzip -cd "$PROJECT_DIR/exports_transfer/users_2026-03-17.gz")"
assert_contains $'1\tAlice|XA|X\n2\t' "$transfer_content" "transferred artifact keeps transformed content"

default_run_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" run --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 default 2>&1)"
assert_contains "[default] Completed successfully." "$default_run_output" "default replacement job succeeds"
assert_true "[[ -f '$PROJECT_DIR/exports/default_2026-03-17.csv' ]]" "default export file created"
default_content="$(cat "$PROJECT_DIR/exports/default_2026-03-17.csv")"
assert_contains $'1\tAlice|?A|?\n2\t' "$default_content" "uses |? default replacement when key is absent"
rm -rf "$PROJECT_DIR/exports" "$PROJECT_DIR/exports_transfer"

if "$ROOT_DIR/bin/exportctl.sh" run >/dev/null 2>&1; then
  echo "FAIL: expected invalid args to exit non-zero" >&2
  exit 1
fi

if "$ROOT_DIR/bin/exportctl.sh" password encode >/dev/null 2>&1; then
  echo "FAIL: expected password command to exit non-zero" >&2
  exit 1
fi

echo "OK: exportctl_test.sh"
