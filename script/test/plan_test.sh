#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/config/properties.sh"
source "$ROOT_DIR/lib/export/plan.sh"
source "$ROOT_DIR/lib/sql/render.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/pwd"
printf 'key' >"$TMP_DIR/key"

cat >"$TMP_DIR/all.properties" <<EOF
primary.DB_HOST=localhost
primary.DB_PORT=3306
primary.DB_NAME=demo
primary.DB_USER=demo_user
primary.DB_TYPE=mysql
primary.DB_PASSWORD_DIR=$TMP_DIR/pwd
primary.DB_PASSWORD_KEY_FILE=$TMP_DIR/key
job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name
job.users.EXPORT_FILE=./exports/users_\${EXPORT_DATE}.csv
job.users.WHERE=created_at BETWEEN '\${YESTERDAY}' AND '\${TODAY}'
job.users.SPLIT.name=3,2
EOF

declare -A PROPS=()
declare -A RUNTIME=()
declare -A PROFILE=()
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
build_export_plan PROPS users PROFILE JOB PLAN
PLAN[sql]="$(render_select_sql PLAN)"

assert_eq "./exports/users_2026-03-17.csv" "${PLAN[export_file]}" "expanded export file"
assert_eq "name|3|2" "${PLAN[splits]}" "split metadata"
assert_eq "SELECT id,SUBSTRING(name, 1, 3) AS name_part1,SUBSTRING(name, 4, 3) AS name_part2 FROM users WHERE created_at BETWEEN '2026-03-16' AND '2026-03-17'" "${PLAN[sql]}" "rendered sql"

echo "OK: plan_test.sh"
