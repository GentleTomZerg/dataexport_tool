#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: $msg" >&2
    echo "  expected to contain: [$needle]" >&2
    exit 1
  fi
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

DB_PROPS="$TMP_DIR/env.properties"
DATA_PROPS="$TMP_DIR/data_export.properties"

cat > "$DB_PROPS" <<'PROPS'
primary.DB_HOST=localhost
primary.DB_PORT=3306
primary.DB_NAME=example_db
primary.DB_USER=example_user
primary.DB_TYPE=mysql

reporting.DB_HOST=rep-host
reporting.DB_PORT=5432
reporting.DB_NAME=rep_db
reporting.DB_USER=rep_user
reporting.DB_TYPE=postgres
PROPS

cat > "$DATA_PROPS" <<'PROPS'
job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name,email
job.users.EXPORT_FILE=./exports/users_${EXPORT_DATE}.csv
job.users.FILTER.status=active

job.orders.DB_PROFILE=reporting
job.orders.TABLE_NAME=orders
job.orders.COLUMNS=id,total,created_at
job.orders.EXPORT_FILE=./exports/orders_${EXPORT_DATE}.csv
job.orders.FILTER.total.op=>=
job.orders.FILTER.total.value=100
PROPS

# 1) Run all jobs with a fixed date.
output_all="$($ROOT_DIR/export_data.sh --db-props "$DB_PROPS" --data-props "$DATA_PROPS" --date 2026-03-17)"
assert_contains "== Job: users ==" "$output_all" "all jobs contains users"
assert_contains "== Job: orders ==" "$output_all" "all jobs contains orders"
assert_contains "DB_PROFILE=primary" "$output_all" "users DB profile"
assert_contains "DB_PROFILE=reporting" "$output_all" "orders DB profile"
assert_contains "EXPORT_FILE=./exports/users_2026-03-17.csv" "$output_all" "users export file"
assert_contains "EXPORT_FILE=./exports/orders_2026-03-17.csv" "$output_all" "orders export file"
assert_contains "SQL=SELECT id,name,email FROM users WHERE status = 'active'" "$output_all" "users SQL"
assert_contains "SQL=SELECT id,total,created_at FROM orders WHERE total >= '100'" "$output_all" "orders SQL"

# 2) Run a specific job.
output_one="$($ROOT_DIR/export_data.sh --db-props "$DB_PROPS" --data-props "$DATA_PROPS" --job users --date 2026-03-17)"
assert_contains "== Job: users ==" "$output_one" "single job users"
if [[ "$output_one" == *"== Job: orders =="* ]]; then
  echo "FAIL: single job should not include orders" >&2
  exit 1
fi

# 3) No jobs and no --job/--jobs should fail.
cat > "$DATA_PROPS" <<'PROPS'
# empty
PROPS
if $ROOT_DIR/export_data.sh --db-props "$DB_PROPS" --data-props "$DATA_PROPS" --date 2026-03-17 >/dev/null 2>&1; then
  echo "FAIL: expected missing jobs to fail" >&2
  exit 1
fi

echo "OK: export_data_test.sh"
