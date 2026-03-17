#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/job_config.sh"

# Simple assertion helpers for readable test output.
assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $msg" >&2
    echo "  expected: [$expected]" >&2
    echo "  actual:   [$actual]" >&2
    exit 1
  fi
}

assert_true() {
  local cond="$1"
  local msg="$2"
  if ! eval "$cond"; then
    echo "FAIL: $msg" >&2
    exit 1
  fi
}

# Run a command in a subshell and expect it to fail.
assert_fail() {
  local msg="$1"
  shift
  if ("$@") >/dev/null 2>&1; then
    echo "FAIL: $msg" >&2
    exit 1
  fi
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROPS_FILE="$TMP_DIR/jobs.properties"
cat > "$PROPS_FILE" <<'PROPS'
job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name,email
job.users.EXPORT_FILE=./exports/users_${EXPORT_DATE}.csv
job.users.FILTER.status=active
job.users.FILTER.name.value=%bob%
job.users.FILTER.name.op=LIKE
job.users.FILTER.signup.op=BETWEEN
job.users.FILTER.signup.from=2024-01-01
job.users.FILTER.signup.to=2024-01-31

job.orders.TABLE_NAME=orders
job.orders.COLUMNS=id,total,created_at
# No DB_PROFILE or EXPORT_FILE for orders
job.orders.FILTER.total.value=100
job.orders.FILTER.total.op=>=

# Broken job (missing columns)
job.broken.TABLE_NAME=broken_table
PROPS

# Provide a runtime variable used in EXPORT_FILE expansion.
EXPORT_DATE="2026-03-17"
export EXPORT_DATE

load_properties "$PROPS_FILE"

# list_jobs should discover entries (including broken).
mapfile -t jobs < <(list_jobs)
assert_true "[[ ${#jobs[@]} -eq 3 ]]" "list_jobs count"

# Load users job.
load_job_config "users"
assert_eq "users" "$DATA_JOB" "job name"
assert_eq "primary" "$DATA_DB_PROFILE" "db profile"
assert_eq "users" "$DATA_TABLE" "table name"
assert_eq "id,name,email" "$DATA_COLUMNS" "columns"
assert_eq "./exports/users_2026-03-17.csv" "$DATA_EXPORT_FILE" "export file expansion"

# Filters: collect and compare as a set because order is not guaranteed.
load_job_filters "users"
mapfile -t filters < <(printf '%s\n' "${DATA_FILTERS[@]}" | sort)
mapfile -t expected < <(cat <<'EXPECT' | sort
name|LIKE|%bob%
status|=|active
signup|BETWEEN|2024-01-01|2024-01-31
EXPECT
)
assert_eq "${expected[*]}" "${filters[*]}" "users filters set"

# Orders job: no DB_PROFILE/EXPORT_FILE, single filter with op.
load_job_config "orders"
assert_eq "" "$DATA_DB_PROFILE" "orders db profile empty"
assert_eq "" "$DATA_EXPORT_FILE" "orders export file empty"
load_job_filters "orders"
assert_eq "total|>=|100" "${DATA_FILTERS[0]}" "orders filter"

# Broken job should fail.
assert_fail "broken job should fail" load_job_config "broken"

echo "OK: job_config_test.sh"
