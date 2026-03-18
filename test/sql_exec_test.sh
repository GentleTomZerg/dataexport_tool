#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/sql_exec.sh"

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
DB_HOST="localhost"
DB_PORT="3306"
DB_USER="user"
DB_NAME="db"
export DB_HOST DB_PORT DB_USER DB_NAME

# 1) MySQL with password file: uses MYSQL_PWD and applies separators.
DB_TYPE="mysql"
DB_PASSWORD_FILE="$TMP_DIR/localhost_3306_user.pwd"
export DB_TYPE DB_PASSWORD_FILE
printf 'dummy' >"$DB_PASSWORD_FILE"

out_file="$TMP_DIR/mysql.out"
DATA_FIELD_SEPARATOR="|"
DATA_LINE_TERMINATOR="\\n"
export DATA_FIELD_SEPARATOR DATA_LINE_TERMINATOR

sql_exec_export "SELECT 1" "$out_file"
printf '1|Alice\n2|Bob\n' >"$TMP_DIR/expected_mysql.out"
assert_true "cmp -s '$TMP_DIR/expected_mysql.out' '$out_file'" "mysql output formatting"
assert_eq "secret" "$(cat "$MYSQL_LOG.pwd")" "mysql password from file"

# 2) Postgres with password file: uses PGPASSWORD and applies separators.
DB_TYPE="postgres"
DB_PORT="5432"
DB_PASSWORD_FILE="$TMP_DIR/localhost_5432_user.pwd"
export DB_TYPE DB_PORT DB_PASSWORD_FILE
printf 'dummy' >"$DB_PASSWORD_FILE"

out_file="$TMP_DIR/psql.out"
DATA_FIELD_SEPARATOR=","
DATA_LINE_TERMINATOR="\\r\\n"
export DATA_FIELD_SEPARATOR DATA_LINE_TERMINATOR

sql_exec_export "SELECT 1" "$out_file"
printf '1,Alice\r\n2,Bob\r\n' >"$TMP_DIR/expected_psql.out"
assert_true "cmp -s '$TMP_DIR/expected_psql.out' '$out_file'" "postgres output formatting"
assert_eq "secret" "$(cat "$PSQL_LOG.pwd")" "postgres password from file"

# 3) MySQL without password file: no MYSQL_PWD used.
DB_TYPE="mysql"
DB_PASSWORD_FILE="$TMP_DIR/missing.pwd"
export DB_TYPE DB_PASSWORD_FILE
rm -f "$MYSQL_LOG.pwd"

out_file="$TMP_DIR/mysql.nopwd.out"
DATA_FIELD_SEPARATOR=","
DATA_LINE_TERMINATOR="\\n"
export DATA_FIELD_SEPARATOR DATA_LINE_TERMINATOR

sql_exec_export "SELECT 1" "$out_file"
assert_true "[[ ! -f '$MYSQL_LOG.pwd' || ! -s '$MYSQL_LOG.pwd' ]]" "mysql no password used"

echo "OK: sql_exec_test.sh"
