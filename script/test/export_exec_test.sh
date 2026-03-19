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
export MYSQL_LOG

cat > "$FAKE_BIN/mysql" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MYSQL_LOG"
# Emit tab-separated rows.
printf '1\tAlice\n2\tBob\n'
FAKE
chmod +x "$FAKE_BIN/mysql"

DB_PROPS="$TMP_DIR/env.properties"
DATA_PROPS="$TMP_DIR/export_jobs.properties"
OUT_FILE="$TMP_DIR/exports/users_out.txt"

cat > "$DB_PROPS" <<'PROPS'
primary.DB_HOST=localhost
primary.DB_PORT=3306
primary.DB_NAME=example_db
primary.DB_USER=example_user
primary.DB_TYPE=mysql
DB_PASSWORD_DIR=./etc/local/pwd
PROPS

cat > "$DATA_PROPS" <<'PROPS'
job.users.DB_PROFILE=primary
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name
job.users.EXPORT_FILE=__OUT_FILE__
job.users.FIELD_SEPARATOR=|
job.users.LINE_TERMINATOR=\n
PROPS

# Inject the output path.
sed -i "s#__OUT_FILE__#$OUT_FILE#" "$DATA_PROPS"

PATH="$FAKE_BIN:$PATH" \
  "$ROOT_DIR/bin/export_data.sh" --db-config "$DB_PROPS" --jobs-config "$DATA_PROPS" --job users --date 2026-03-17 --execute >/dev/null

assert_true "[[ -f '$OUT_FILE' ]]" "export output file exists"
printf '1|Alice\n2|Bob\n' >"$TMP_DIR/expected_export.out"
assert_true "cmp -s '$TMP_DIR/expected_export.out' '$OUT_FILE'" "export output formatting"

# Ensure mysql was invoked.
assert_true "[[ -s '$MYSQL_LOG' ]]" "mysql invoked"

echo "OK: export_exec_test.sh"
