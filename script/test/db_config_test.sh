#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/db_config.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS_DIR="$TMP_DIR/secrets"
KEY_FILE="$TMP_DIR/key_file"
mkdir -p "$PASS_DIR"
printf 'test-key' >"$KEY_FILE"

PROPS_FILE="$TMP_DIR/db.properties"
cat > "$PROPS_FILE" <<PROPS
# Primary profile (complete)
primary.DB_HOST=localhost
primary.DB_PORT=3306
primary.DB_NAME=example_db
primary.DB_USER=example_user
primary.DB_TYPE=mysql
primary.DB_PASSWORD_DIR=$PASS_DIR
primary.DB_PASSWORD_KEY_FILE=$KEY_FILE

# Reporting profile (complete, with type)
reporting.DB_HOST=rep-host
reporting.DB_PORT=5432
reporting.DB_NAME=rep_db
reporting.DB_USER=rep_user
reporting.DB_TYPE=postgres
reporting.DB_PASSWORD_DIR=$PASS_DIR
reporting.DB_PASSWORD_KEY_FILE=$KEY_FILE

# Incomplete profile for failure case
broken.DB_HOST=only_host
PROPS

touch "$PASS_DIR/localhost_3306_example_user.pwd"
touch "$PASS_DIR/rep-host_5432_rep_user.pwd"

load_properties "$PROPS_FILE"

# Primary should load with required DB_TYPE.
load_db_profile "primary"
assert_eq "localhost" "${DB[host]}" "load primary host"
assert_eq "3306" "${DB[port]}" "load primary port"
assert_eq "example_db" "${DB[name]}" "load primary name"
assert_eq "example_user" "${DB[user]}" "load primary user"
assert_eq "mysql" "${DB[type]}" "load DB_TYPE"
assert_eq "$PASS_DIR/localhost_3306_example_user.pwd" "${DB[password_file]}" "password file path export"
assert_eq "$PASS_DIR/localhost_3306_example_user.pwd" "$(db_password_file)" "password file path"
assert_eq "$KEY_FILE" "${DB[password_key_file]}" "password key file"

# Reporting profile should load its explicit DB_TYPE.
load_db_profile "reporting"
assert_eq "rep-host" "${DB[host]}" "load reporting host"
assert_eq "5432" "${DB[port]}" "load reporting port"
assert_eq "rep_db" "${DB[name]}" "load reporting name"
assert_eq "rep_user" "${DB[user]}" "load reporting user"
assert_eq "postgres" "${DB[type]}" "use explicit DB_TYPE"
assert_eq "$KEY_FILE" "${DB[password_key_file]}" "password key file"

# Missing profile should fail.
assert_fail "missing profile should fail" load_db_profile "missing"

# Incomplete profile should fail.
assert_fail "incomplete profile should fail" load_db_profile "broken"

echo "OK: db_config_test.sh"
