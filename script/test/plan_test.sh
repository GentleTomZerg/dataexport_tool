#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/config/properties.sh"
source "$ROOT_DIR/lib/exportctl/model/plan.sh"
source "$ROOT_DIR/lib/exportctl/sql.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/pwd"
printf 'key' >"$TMP_DIR/key"
echo -n "testpassword" | openssl des3 -salt -in /dev/stdin -out "$TMP_DIR/pwd/localhost_3306_demo_user.pwd" -pass file:"$TMP_DIR/key" -pbkdf2 -iter 100000

cat >"$TMP_DIR/all.properties" <<EOF
ENV_TEST_DB_TYPE=mysql
ENV_TEST_DB_HOST=localhost
ENV_TEST_DB_PORT=3306
ENV_TEST_DB_NAME=demo
ENV_TEST_DB_USER=demo_user
ENV_TEST_DB_PASSWORD_FILE=$TMP_DIR/pwd/localhost_3306_demo_user.pwd
ENV_TEST_DB_PASSWORD_KEY_FILE=$TMP_DIR/key
job.users.DB_TYPE=\${ENV_TEST_DB_TYPE}
job.users.DB_HOST=\${ENV_TEST_DB_HOST}
job.users.DB_PORT=\${ENV_TEST_DB_PORT}
job.users.DB_NAME=\${ENV_TEST_DB_NAME}
job.users.DB_USER=\${ENV_TEST_DB_USER}
job.users.DB_PASSWORD_FILE=\${ENV_TEST_DB_PASSWORD_FILE}
job.users.DB_PASSWORD_KEY_FILE=\${ENV_TEST_DB_PASSWORD_KEY_FILE}
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name
job.users.EXPORT_FILE=./exports/users_\${EXPORT_DATE}.csv
job.users.WHERE=created_at BETWEEN '\${YESTERDAY}' AND '\${TODAY}'
job.users.SPLIT.name=3,2
EOF

declare -A PROPS=()
declare -A RUNTIME=()
declare -A JOB=()
declare -A PLAN=()

load_props_from_file "$TMP_DIR/all.properties" PROPS
EXPORT_DATE="2026-03-17"
TODAY="2026-03-17"
YESTERDAY="2026-03-16"
EXPORT_MONTH="2026-03"
MONTH_START="2026-03-01"
MONTH_END="2026-03-31"
export EXPORT_DATE TODAY YESTERDAY EXPORT_MONTH MONTH_START MONTH_END
build_export_plan PROPS users PLAN
PLAN[sql]="$(render_select_sql PLAN)"

assert_eq "./exports/users_2026-03-17.csv" "${PLAN[export_file]}" "expanded export file"
assert_eq "name|3|2" "${PLAN[splits]}" "split metadata"
assert_eq "SELECT id,SUBSTRING(name, 1, 3) AS name_part1,SUBSTRING(name, 4, 3) AS name_part2 FROM users WHERE created_at BETWEEN '2026-03-16' AND '2026-03-17'" "${PLAN[sql]}" "rendered sql"

echo "OK: plan_test.sh"
