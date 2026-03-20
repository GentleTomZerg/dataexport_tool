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

PASS_DIR="$TMP_DIR/pwd"
KEY_FILE="$TMP_DIR/key_file"
mkdir -p "$PASS_DIR"
printf 'test-key' >"$KEY_FILE"
touch "$PASS_DIR/localhost_3306_example_user.pwd"
touch "$PASS_DIR/rep-host_5432_rep_user.pwd"

DB_PROPS="$TMP_DIR/env.properties"
DATA_PROPS="$TMP_DIR/export_jobs.properties"

cat > "$DB_PROPS" <<PROPS
primary.DB_HOST=localhost
primary.DB_PORT=3306
primary.DB_NAME=example_db
primary.DB_USER=example_user
primary.DB_TYPE=mysql
primary.DB_PASSWORD_DIR=$PASS_DIR
primary.DB_PASSWORD_KEY_FILE=$KEY_FILE

reporting.DB_HOST=rep-host
reporting.DB_PORT=5432
reporting.DB_NAME=rep_db
reporting.DB_USER=rep_user
reporting.DB_TYPE=postgres
reporting.DB_PASSWORD_DIR=$PASS_DIR
reporting.DB_PASSWORD_KEY_FILE=$KEY_FILE
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

job.daily_events.DB_PROFILE=primary
job.daily_events.TABLE_NAME=events
job.daily_events.COLUMNS=id,type,created_at
job.daily_events.EXPORT_FILE=./exports/events_${YESTERDAY}.csv
job.daily_events.FILTER.created_at.op=BETWEEN
job.daily_events.FILTER.created_at.from=${YESTERDAY}
job.daily_events.FILTER.created_at.to=${TODAY}

job.monthly_events.DB_PROFILE=primary
job.monthly_events.TABLE_NAME=events
job.monthly_events.COLUMNS=id,type,created_at
job.monthly_events.EXPORT_FILE=./exports/events_${EXPORT_MONTH}.csv
job.monthly_events.FILTER.created_at.op=BETWEEN
job.monthly_events.FILTER.created_at.from=${MONTH_START}
job.monthly_events.FILTER.created_at.to=${MONTH_END}
PROPS

# 1) Run all jobs with a fixed date.
output_all="$($ROOT_DIR/bin/export_data.sh --db-config "$DB_PROPS" --jobs-config "$DATA_PROPS" --date 2026-03-17)"
assert_contains "== Job: users ==" "$output_all" "all jobs contains users"
assert_contains "== Job: orders ==" "$output_all" "all jobs contains orders"
assert_contains "== Job: daily_events ==" "$output_all" "all jobs contains daily_events"
assert_contains "== Job: monthly_events ==" "$output_all" "all jobs contains monthly_events"
assert_contains "DB_PROFILE=primary" "$output_all" "users DB profile"
assert_contains "DB_PROFILE=reporting" "$output_all" "orders DB profile"
assert_contains "EXPORT_FILE=./exports/users_2026-03-17.csv" "$output_all" "users export file"
assert_contains "EXPORT_FILE=./exports/orders_2026-03-17.csv" "$output_all" "orders export file"
assert_contains "EXPORT_FILE=./exports/events_2026-03-16.csv" "$output_all" "daily events export file"
assert_contains "EXPORT_FILE=./exports/events_2026-03.csv" "$output_all" "monthly events export file"
assert_contains "SQL=SELECT id,name,email FROM users WHERE status = 'active'" "$output_all" "users SQL"
assert_contains "SQL=SELECT id,total,created_at FROM orders WHERE total >= '100'" "$output_all" "orders SQL"
assert_contains "SQL=SELECT id,type,created_at FROM events WHERE created_at BETWEEN '2026-03-16' AND '2026-03-17'" "$output_all" "daily events SQL"
assert_contains "SQL=SELECT id,type,created_at FROM events WHERE created_at BETWEEN '2026-03-01' AND '2026-03-31'" "$output_all" "monthly events SQL"

# 2) Run a specific job.
output_one="$($ROOT_DIR/bin/export_data.sh --db-config "$DB_PROPS" --jobs-config "$DATA_PROPS" --job users --date 2026-03-17)"
assert_contains "== Job: users ==" "$output_one" "single job users"
if [[ "$output_one" == *"== Job: orders =="* ]]; then
  echo "FAIL: single job should not include orders" >&2
  exit 1
fi

# 3) No jobs and no --job/--jobs should fail.
cat > "$DATA_PROPS" <<'PROPS'
# empty
PROPS
if $ROOT_DIR/bin/export_data.sh --db-config "$DB_PROPS" --jobs-config "$DATA_PROPS" --date 2026-03-17 >/dev/null 2>&1; then
  echo "FAIL: expected missing jobs to fail" >&2
  exit 1
fi

echo "OK: export_data_test.sh"
