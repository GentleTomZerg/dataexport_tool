#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/pwd" "$TMP_DIR/bin"
printf 'key' >"$TMP_DIR/key"

cat >"$TMP_DIR/bin/mysql" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '1\tAlice\n'
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

cat >"$TMP_DIR/jobs.properties" <<'EOF'
job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id
job.users.EXPORT_FILE=./users.csv
job.orders.DB_PROFILE=primary
job.orders.TABLE_NAME=orders
job.orders.COLUMNS=id
job.orders.EXPORT_FILE=./orders.csv
EOF

output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" plan --db-config "$TMP_DIR/db.properties" --jobs-config "$TMP_DIR/jobs.properties" users orders 2>&1)"
assert_contains "== Job: orders ==" "$output" "orders selected"
assert_contains "== Job: users ==" "$output" "users selected"
assert_true "[[ \"$output\" != *\"unknown selector\"* ]]" "known selectors only"

echo "OK: selector_test.sh"
