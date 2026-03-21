#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/sql_exec.sh"

declare -Ag JOB

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

MYSQL_LOG="$TMP_DIR/mysql.log"
PSQL_LOG="$TMP_DIR/psql.log"

cat > "$FAKE_BIN/mysql" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MYSQL_LOG"
if [[ -n "${MYSQL_PWD:-}" ]]; then
  printf '%s' "$MYSQL_PWD" >"$MYSQL_LOG.pwd"
fi
# Emit tab-separated rows.
printf '1\tAlice\n2\tBob\n'
FAKE

cat > "$FAKE_BIN/psql" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$PSQL_LOG"
if [[ -n "${PGPASSWORD:-}" ]]; then
  printf '%s' "$PGPASSWORD" >"$PSQL_LOG.pwd"
fi
# Emit tab-separated rows (copy to stdout behavior).
printf '1\tAlice\n2\tBob\n'
FAKE

chmod +x "$FAKE_BIN/mysql" "$FAKE_BIN/psql"

export PATH="$FAKE_BIN:$PATH"
export MYSQL_LOG PSQL_LOG

# Stub decrypt_password to avoid openssl.
decrypt_password() {
  echo "secret"
}

# Common DB settings.
declare -Ag DB
DB[host]="localhost"
DB[port]="3306"
DB[user]="user"
DB[name]="db"
export DB

# 1) MySQL with password file: uses MYSQL_PWD and applies separators.
DB[type]="mysql"
DB[password_file]="$TMP_DIR/localhost_3306_user.pwd"
export DB
printf 'dummy' >"${DB[password_file]}"

out_file="$TMP_DIR/mysql.out"
JOB[field_separator]="|"
JOB[line_terminator]="\\n"
export JOB

sql_exec_export "SELECT 1" "$out_file"
printf '1|Alice\n2|Bob\n' >"$TMP_DIR/expected_mysql.out"
assert_true "cmp -s '$TMP_DIR/expected_mysql.out' '$out_file'" "mysql output formatting"
assert_eq "secret" "$(cat "$MYSQL_LOG.pwd")" "mysql password from file"

# 2) Postgres with password file: uses PGPASSWORD and applies separators.
DB[type]="postgres"
DB[port]="5432"
DB[password_file]="$TMP_DIR/localhost_5432_user.pwd"
export DB
printf 'dummy' >"${DB[password_file]}"

out_file="$TMP_DIR/psql.out"
JOB[field_separator]=","
JOB[line_terminator]="\\r\\n"
export JOB

sql_exec_export "SELECT 1" "$out_file"
printf '1,Alice\r\n2,Bob\r\n' >"$TMP_DIR/expected_psql.out"
assert_true "cmp -s '$TMP_DIR/expected_psql.out' '$out_file'" "postgres output formatting"
assert_eq "secret" "$(cat "$PSQL_LOG.pwd")" "postgres password from file"

# 3) MySQL without password file: no MYSQL_PWD used.
DB[type]="mysql"
DB[password_file]="$TMP_DIR/missing.pwd"
export DB
rm -f "$MYSQL_LOG.pwd"

out_file="$TMP_DIR/mysql.nopwd.out"
JOB[field_separator]=","
JOB[line_terminator]="\\n"
export JOB

sql_exec_export "SELECT 1" "$out_file"
assert_true "[[ ! -f '$MYSQL_LOG.pwd' || ! -s '$MYSQL_LOG.pwd' ]]" "mysql no password used"

echo "OK: sql_exec_test.sh"
