#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/pwd" "$TMP_DIR/bin"
printf 'key' >"$TMP_DIR/key"
echo -n "testpassword" | openssl des3 -salt -in /dev/stdin -out "$TMP_DIR/pwd/localhost_3306_demo_user.pwd" -pass file:"$TMP_DIR/key" -pbkdf2 -iter 100000

cat >"$TMP_DIR/bin/mysql" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '1\tAlice\n'
EOF
chmod +x "$TMP_DIR/bin/mysql"

cat >"$TMP_DIR/env.properties" <<EOF
ENV_TEST_DB_HOST=localhost
ENV_TEST_DB_PORT=3306
ENV_TEST_DB_NAME=demo
ENV_TEST_DB_USER=demo_user
ENV_TEST_DB_TYPE=mysql
ENV_TEST_DB_PASSWORD_FILE=$TMP_DIR/pwd/localhost_3306_demo_user.pwd
ENV_TEST_DB_PASSWORD_KEY_FILE=$TMP_DIR/key
EOF

cat >"$TMP_DIR/jobs.properties" <<'EOF'
job.users.DB_PROFILE=ENV_TEST_DB
job.users.TABLE_NAME=users
job.users.COLUMNS=id
job.users.EXPORT_FILE=./users.csv
job.orders.DB_PROFILE=ENV_TEST_DB
job.orders.TABLE_NAME=orders
job.orders.COLUMNS=id
job.orders.EXPORT_FILE=./orders.csv
EOF

output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" plan --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" users orders 2>&1)"
assert_contains "== Job: orders ==" "$output" "orders selected"
assert_contains "== Job: users ==" "$output" "users selected"
assert_true "[[ \"$output\" != *\"unknown job\"* ]]" "known jobs only"

echo "OK: selector_test.sh"
