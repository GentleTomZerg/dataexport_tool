#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/config/properties.sh"
source "$ROOT_DIR/lib/export/selector.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/jobs.properties" <<'EOF'
job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id
job.users.EXPORT_FILE=./users.csv
job.users.GROUPS=daily,core
job.orders.DB_PROFILE=primary
job.orders.TABLE_NAME=orders
job.orders.COLUMNS=id
job.orders.EXPORT_FILE=./orders.csv
job.orders.GROUPS=daily
EOF

declare -A PROPS=()
load_props_from_file "$TMP_DIR/jobs.properties" PROPS
selectors=("group:daily" "users")
resolved=()
resolve_job_selectors PROPS selectors resolved
assert_eq "orders users" "${resolved[*]}" "selector resolution"

echo "OK: selector_test.sh"
