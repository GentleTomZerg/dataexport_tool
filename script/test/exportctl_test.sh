#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$ROOT_DIR/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/pwd" "$TMP_DIR/bin"
printf 'key' >"$TMP_DIR/key"

cat >"$TMP_DIR/bin/mysql" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '1\tAlice\n2\tBob\n'
EOF
chmod +x "$TMP_DIR/bin/mysql"

cat >"$TMP_DIR/db.properties" <<EOF
primary.DB_HOST=localhost
primary.DB_PORT=3306
primary.DB_NAME=demo
primary.DB_USER=demo_user
primary.DB_TYPE=mysql
primary.DB_PASSWORD_DIR=$TMP_DIR/pwd
primary.DB_PASSWORD_KEY_FILE=$TMP_DIR/key
EOF

cat >"$TMP_DIR/env.properties" <<'EOF'
ENV_EXPORT_ROOT=./exports
ENV_TRANSFER_ROOT=./exports_transfer
EOF

cat >"$TMP_DIR/jobs.properties" <<'EOF'
job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name
job.users.EXPORT_FILE=${ENV_EXPORT_ROOT}/users_${EXPORT_DATE}.csv
job.users.WHERE=status = 'active'
job.users.COMPRESS.ENABLED=true
job.users.COMPRESS.MODE=gz
job.users.COMPRESS.OVERWRITE=true
job.users.TRANSFER.ENABLED=true
job.users.TRANSFER.DIR=${ENV_TRANSFER_ROOT}
job.users.TRANSFER.MODE=copy
job.users.TRANSFER.OVERWRITE=true
job.users.TRANSFER.RENAME=users_${EXPORT_DATE}.gz
job.bad.TABLE_NAME=bad
job.bad.COLUMNS=id
job.bad.EXPORT_FILE=${ENV_EXPORT_ROOT}/bad.csv
EOF

plan_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl" plan --db-config "$TMP_DIR/db.properties" --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 2>&1)"
assert_contains "== Job: users ==" "$plan_output" "plan includes users"
assert_contains "== Job: bad ==" "$plan_output" "failed job header printed"
assert_contains "STATUS=FAILED" "$plan_output" "failed job status printed"
assert_contains "JOB_FAIL name=bad" "$plan_output" "bad job logged"
assert_contains "SUMMARY total=2 ok=1 failed=1" "$plan_output" "summary counts"
assert_contains "== Environment ==" "$plan_output" "environment block printed"
assert_contains "ENV_EXPORT_ROOT=./exports" "$plan_output" "export env printed"
assert_contains "SQL=SELECT id,name FROM users WHERE status = 'active'" "$plan_output" "plan prints sql"

validate_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl" validate --db-config "$TMP_DIR/db.properties" --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 2>&1)"
assert_contains "== Job: users ==" "$validate_output" "validate includes users"
assert_contains "STATUS=OK" "$validate_output" "validate prints ok status"
assert_contains "STATUS=FAILED" "$validate_output" "validate prints failed status"
assert_true "[[ \"$validate_output\" != *\"SQL=\"* ]]" "validate should not print sql"

unknown_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl" plan --db-config "$TMP_DIR/db.properties" --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 users missing_job 2>&1)"
assert_contains "ERROR: unknown selector missing_job" "$unknown_output" "unknown selector logged"

run_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl" run --db-config "$TMP_DIR/db.properties" --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 users 2>&1)"
assert_contains "JOB_INFO name=users stage=export_start" "$run_output" "export start log"
assert_contains "JOB_INFO name=users stage=export_ok file=./exports/users_2026-03-17.csv lines=2" "$run_output" "export metrics log"
assert_contains "JOB_INFO name=users stage=compress_start file=./exports/users_2026-03-17.csv mode=gz" "$run_output" "compress start log"
assert_contains "JOB_INFO name=users stage=compress_ok src=./exports/users_2026-03-17.csv dest=./exports/users_2026-03-17.csv.gz mode=gz remove_original=false" "$run_output" "compress ok log"
assert_contains "JOB_INFO name=users stage=transfer_start file=./exports/users_2026-03-17.csv.gz dir=./exports_transfer mode=copy" "$run_output" "transfer start log"
assert_contains "JOB_INFO name=users stage=transfer_ok src=./exports/users_2026-03-17.csv.gz dest=./exports_transfer/users_2026-03-17.gz mode=copy" "$run_output" "transfer ok log"
assert_contains "JOB_INFO name=users stage=artifact_ok file=./exports_transfer/users_2026-03-17.gz" "$run_output" "final artifact log"
assert_contains "JOB_OK name=users" "$run_output" "run success log"
assert_true "[[ -f '$PROJECT_DIR/exports/users_2026-03-17.csv' ]]" "export file created"
assert_true "[[ -f '$PROJECT_DIR/exports/users_2026-03-17.csv.gz' ]]" "compressed file created"
assert_true "[[ -f '$PROJECT_DIR/exports_transfer/users_2026-03-17.gz' ]]" "transferred file created"
rm -rf "$PROJECT_DIR/exports" "$PROJECT_DIR/exports_transfer"

if "$ROOT_DIR/bin/exportctl" run --db-config >/dev/null 2>&1; then
  echo "FAIL: expected invalid args to exit non-zero" >&2
  exit 1
fi

echo "OK: exportctl_test.sh"
