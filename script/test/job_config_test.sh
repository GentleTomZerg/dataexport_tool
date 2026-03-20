#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/job_config.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROPS_FILE="$TMP_DIR/jobs.properties"
cat > "$PROPS_FILE" <<'PROPS'
job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name,email,notes,content
job.users.EXPORT_FILE=./exports/users_${EXPORT_DATE}.csv
job.users.FIELD_SEPARATOR=|
job.users.LINE_TERMINATOR=\r\n
job.users.WHERE=status = 'active' AND name LIKE '%bob%'
job.users.SPLIT.content=4000,3
job.users.SPLIT.notes=2000,2

job.orders.TABLE_NAME=orders
job.orders.COLUMNS=id,total,created_at
job.orders.WHERE=total >= 100

job.monthly_events.TABLE_NAME=events
job.monthly_events.COLUMNS=id,type,created_at
job.monthly_events.EXPORT_FILE=./exports/events_${EXPORT_MONTH}.csv
job.monthly_events.WHERE=created_at BETWEEN '${MONTH_START}' AND '${MONTH_END}'

# Broken job (missing columns)
job.broken.TABLE_NAME=broken_table
PROPS

# Provide runtime variables used in expansion.
EXPORT_DATE="2026-03-17"
export EXPORT_DATE
MONTH_START="2026-03-01"
export MONTH_START
MONTH_END="2026-03-31"
export MONTH_END

load_properties "$PROPS_FILE"

# list_jobs should discover entries (including broken and date-based).
mapfile -t jobs < <(list_jobs)
assert_true "[[ ${#jobs[@]} -eq 4 ]]" "list_jobs count"

# Load users job.
load_job_config "users"
assert_eq "users" "${JOB[name]}" "job name"
assert_eq "primary" "${JOB[db_profile]}" "db profile"
assert_eq "users" "${JOB[table]}" "table name"
assert_eq "id,name,email,notes,content" "${JOB[columns]}" "columns"
assert_eq "./exports/users_2026-03-17.csv" "${JOB[export_file]}" "export file expansion"
assert_eq "|" "${JOB[field_separator]}" "field separator"
assert_eq "\\r\\n" "${JOB[line_terminator]}" "line terminator"
assert_eq "status = 'active' AND name LIKE '%bob%'" "${JOB[where]}" "where clause"

# Split columns.
load_job_splits "users"
validate_job_splits "users"
mapfile -t splits < <(printf '%s\n' "${JOB_SPLITS[@]}" | sort)
mapfile -t expected_splits < <(cat <<'EXPECT' | sort
content|4000|3
notes|2000|2
EXPECT
)
assert_eq "${expected_splits[*]}" "${splits[*]}" "users split set"

# Orders job: WHERE without FILTER.
load_job_config "orders"
assert_eq "total >= 100" "${JOB[where]}" "orders where clause"
assert_eq "" "${JOB[db_profile]}" "orders db profile empty"
assert_eq "" "${JOB[export_file]}" "orders export file empty"
assert_eq "\\t" "${JOB[field_separator]}" "orders field separator default"
assert_eq "\\n" "${JOB[line_terminator]}" "orders line terminator default"

# Monthly events job: WHERE with ${VAR} expansion.
load_job_config "monthly_events"
assert_eq "created_at BETWEEN '2026-03-01' AND '2026-03-31'" "${JOB[where]}" "monthly events where expansion"

# Job without WHERE: should be empty.
cat > "$PROPS_FILE" <<'PROPS'
job.nowhere.TABLE_NAME=t
job.nowhere.COLUMNS=id
PROPS
load_properties "$PROPS_FILE"
load_job_config "nowhere"
assert_eq "" "${JOB[where]}" "no where clause"

# Broken job should fail.
assert_fail "broken job should fail" load_job_config "broken"

echo "OK: job_config_test.sh"
