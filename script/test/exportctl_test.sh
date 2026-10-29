#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$ROOT_DIR/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"

cd "$PROJECT_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

rm -rf "$PROJECT_DIR/exports" "$PROJECT_DIR/exports_transfer"

mkdir -p "$TMP_DIR/pwd" "$TMP_DIR/bin"
printf 'key' >"$TMP_DIR/key"
echo -n "testpassword" | openssl des3 -salt -in /dev/stdin -out "$TMP_DIR/pwd/localhost_3306_demo_user.pwd" -pass file:"$TMP_DIR/key" -pbkdf2 -iter 100000

cat >"$TMP_DIR/bin/mysql" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Fake client. Default output is the classic two-row case. With FAKE_MYSQL_TSV_FILE
# it models what the real client does, so the tests fail if --raw comes back:
#   --batch: NUL/tab/LF/backslash escaped, but CR left raw
#   --raw:   nothing escaped, so data tab/LF bytes reach the pipeline raw
# In the fixture a data CR is written \r and a data NUL as \0; the client emits
# the CR as a raw byte in either mode, and NUL as \0 in either mode (raw-mode NUL
# is not modelled: awk cannot carry a NUL byte).
raw=0
for arg in "$@"; do
  [[ "$arg" == "--raw" || "$arg" == "-r" ]] && raw=1
done
if [[ -z "${FAKE_MYSQL_TSV_FILE:-}" ]]; then
  printf '1\tAlice|!A|!\n2\tNULL\n'
  exit 0
fi
awk -v raw="$raw" '
  # Byte codes, spelled out: 92 = backslash, 13 = CR, 9 = tab, 10 = LF.
  function unescape(s,   out, i, n, c, nx, bs) {
    bs = sprintf("%c", 92)
    out = ""; n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (c != bs) { out = out c; continue }
      nx = substr(s, i + 1, 1)
      if (nx == "r") { out = out sprintf("%c", 13); i++ }
      else if (nx == "t") { out = out (raw ? sprintf("%c", 9) : bs "t"); i++ }
      else if (nx == "n") { out = out (raw ? sprintf("%c", 10) : bs "n"); i++ }
      else if (nx == bs) { out = out (raw ? bs : bs bs); i++ }
      else out = out c
    }
    return out
  }
  {
    for (i = 1; i <= NF; i++) $i = unescape($i)
    $1 = $1
    print
  }
' FS='\t' OFS='\t' "$FAKE_MYSQL_TSV_FILE"
EOF
chmod +x "$TMP_DIR/bin/mysql"

cat >"$TMP_DIR/env.properties" <<EOF
ENV_EXPORT_ROOT=./exports
ENV_TRANSFER_ROOT=./exports_transfer
ENV_TEST_DB_HOST=localhost
ENV_TEST_DB_PORT=3306
ENV_TEST_DB_NAME=demo
ENV_TEST_DB_USER=demo_user
ENV_TEST_DB_TYPE=mysql
ENV_TEST_DB_PASSWORD_FILE=$TMP_DIR/pwd/localhost_3306_demo_user.pwd
ENV_TEST_DB_PASSWORD_KEY_FILE=$TMP_DIR/key
EOF

cat >"$TMP_DIR/jobs.properties" <<'EOF'
job.users.DB_TYPE=${ENV_TEST_DB_TYPE}
job.users.DB_HOST=${ENV_TEST_DB_HOST}
job.users.DB_PORT=${ENV_TEST_DB_PORT}
job.users.DB_NAME=${ENV_TEST_DB_NAME}
job.users.DB_USER=${ENV_TEST_DB_USER}
job.users.DB_PASSWORD_FILE=${ENV_TEST_DB_PASSWORD_FILE}
job.users.DB_PASSWORD_KEY_FILE=${ENV_TEST_DB_PASSWORD_KEY_FILE}
job.users.TABLE_NAME=users
job.users.COLUMNS=id,name
job.users.EXPORT_FILE=${ENV_EXPORT_ROOT}/users_${EXPORT_DATE}.csv
job.users.FIELD_SEPARATOR_DATA_REPLACEMENT=|X
job.users.WHERE=status = 'active'
job.users.COMPRESS.ENABLED=true
job.users.COMPRESS.MODE=gz
job.users.COMPRESS.OVERWRITE=true
job.users.TRANSFER.ENABLED=true
job.users.TRANSFER.DIR=${ENV_TRANSFER_ROOT}
job.users.TRANSFER.MODE=copy
job.users.TRANSFER.OVERWRITE=true
job.users.TRANSFER.RENAME=users_${EXPORT_DATE}.gz
job.default.DB_TYPE=${ENV_TEST_DB_TYPE}
job.default.DB_HOST=${ENV_TEST_DB_HOST}
job.default.DB_PORT=${ENV_TEST_DB_PORT}
job.default.DB_NAME=${ENV_TEST_DB_NAME}
job.default.DB_USER=${ENV_TEST_DB_USER}
job.default.DB_PASSWORD_FILE=${ENV_TEST_DB_PASSWORD_FILE}
job.default.DB_PASSWORD_KEY_FILE=${ENV_TEST_DB_PASSWORD_KEY_FILE}
job.default.TABLE_NAME=users
job.default.COLUMNS=id,name
job.default.EXPORT_FILE=${ENV_EXPORT_ROOT}/default_${EXPORT_DATE}.csv
job.pipes.DB_TYPE=${ENV_TEST_DB_TYPE}
job.pipes.DB_HOST=${ENV_TEST_DB_HOST}
job.pipes.DB_PORT=${ENV_TEST_DB_PORT}
job.pipes.DB_NAME=${ENV_TEST_DB_NAME}
job.pipes.DB_USER=${ENV_TEST_DB_USER}
job.pipes.DB_PASSWORD_FILE=${ENV_TEST_DB_PASSWORD_FILE}
job.pipes.DB_PASSWORD_KEY_FILE=${ENV_TEST_DB_PASSWORD_KEY_FILE}
job.pipes.TABLE_NAME=users
job.pipes.COLUMNS=id,name
job.pipes.EXPORT_FILE=${ENV_EXPORT_ROOT}/pipes_${EXPORT_DATE}.csv
job.pipes.FIELD_SEPARATOR=|!
job.pipes.LINE_TERMINATOR=@#$\n
job.pipes.FIELD_SEPARATOR_DATA_REPLACEMENT=|?
job.bad.DB_TYPE=mysql
job.bad.DB_HOST=localhost
job.bad.DB_PORT=3306
job.bad.DB_NAME=demo
job.bad.DB_USER=demo_user
job.bad.DB_PASSWORD_FILE=
job.bad.DB_PASSWORD_KEY_FILE=$TMP_DIR/key
job.bad.TABLE_NAME=bad
job.bad.COLUMNS=id
job.bad.EXPORT_FILE=${ENV_EXPORT_ROOT}/bad.csv
EOF

plan_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" plan --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 2>&1)"
assert_contains "== Job: users ==" "$plan_output" "plan includes users"
assert_contains "== Job: bad ==" "$plan_output" "failed job header printed"
assert_contains "[bad] Plan build failed." "$plan_output" "bad job logged"
assert_contains "Summary: total=4 ok=3 failed=1" "$plan_output" "summary counts"
assert_contains "== Environment ==" "$plan_output" "environment block printed"
assert_contains "ENV_EXPORT_ROOT=./exports" "$plan_output" "export env printed"
assert_contains "SQL=SELECT id,name FROM users WHERE status = 'active'" "$plan_output" "plan prints sql"
assert_contains "FILE_SPLIT=disabled" "$plan_output" "plan prints disabled file split"
assert_contains "[users] Plan generated." "$plan_output" "plan success note"

validate_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" validate --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 2>&1)"
assert_contains "== Job: users ==" "$validate_output" "validate includes users"
assert_contains "[bad] Plan build failed." "$validate_output" "validate prints failed job"
assert_contains "[users] Validation succeeded." "$validate_output" "validate success note"
assert_true "[[ \"$validate_output\" != *\"SQL=\"* ]]" "validate should not print sql"

unknown_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" plan --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 users missing_job 2>&1)"
assert_contains "ERROR: unknown job missing_job" "$unknown_output" "unknown job logged"

run_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" run --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 users 2>&1)"
assert_contains "[users] Starting export: db_type=mysql file=./exports/users_2026-03-17.csv" "$run_output" "export start log"
assert_contains "[users] Export finished: file=./exports/users_2026-03-17.csv lines=2" "$run_output" "export metrics log"
assert_contains "[users] Compressing artifact: file=./exports/users_2026-03-17.csv mode=gz" "$run_output" "compress start log"
assert_contains "[users] Compression finished: src=./exports/users_2026-03-17.csv dest=./exports/users_2026-03-17.csv.gz mode=gz remove_original=false" "$run_output" "compress ok log"
assert_contains "[users] Transferring artifact: file=./exports/users_2026-03-17.csv.gz dir=./exports_transfer mode=copy" "$run_output" "transfer start log"
assert_contains "[users] Transfer finished: src=./exports/users_2026-03-17.csv.gz dest=./exports_transfer/users_2026-03-17.gz mode=copy" "$run_output" "transfer ok log"
assert_contains "[users] Final artifact ready: file=./exports_transfer/users_2026-03-17.gz" "$run_output" "final artifact log"
assert_contains "[users] Completed successfully." "$run_output" "run success log"
assert_true "[[ -f '$PROJECT_DIR/exports/users_2026-03-17.csv' ]]" "export file created"
export_content="$(cat "$PROJECT_DIR/exports/users_2026-03-17.csv")"
assert_contains $'1\tAlice|XA|X\n2\t' "$export_content" "sanitizes |! and NULL with configured replacement"
assert_true "[[ -f '$PROJECT_DIR/exports/users_2026-03-17.csv.gz' ]]" "compressed file created"
assert_true "[[ -f '$PROJECT_DIR/exports_transfer/users_2026-03-17.gz' ]]" "transferred file created"
transfer_content="$(gzip -cd "$PROJECT_DIR/exports_transfer/users_2026-03-17.gz")"
assert_contains $'1\tAlice|XA|X\n2\t' "$transfer_content" "transferred artifact keeps transformed content"

default_run_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" run --jobs-config "$TMP_DIR/jobs.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 default 2>&1)"
assert_contains "[default] Completed successfully." "$default_run_output" "default replacement job succeeds"
assert_true "[[ -f '$PROJECT_DIR/exports/default_2026-03-17.csv' ]]" "default export file created"
default_content="$(cat "$PROJECT_DIR/exports/default_2026-03-17.csv")"
assert_contains $'1\tAlice|?A|?\n2\t' "$default_content" "uses |? default replacement when key is absent"
rm -rf "$PROJECT_DIR/exports" "$PROJECT_DIR/exports_transfer"

###############################################################################
# Escaping end to end: data characters never become structure
# (docs/adr/0002-field-data-is-escaped.md)
###############################################################################

# Fixture in the client's escaped form: a value holding a tab, a LF, a separator
# collision and a doubled backslash; then a NULL row and a plain row. The fake
# client decides whether those escapes are emitted as bytes.
printf '1\tA\\tB\\nC|!E\\\\F\\0N\n2\tNULL\n3\tplain\n' >"$TMP_DIR/escaped.tsv"
FAKE_MYSQL_TSV_FILE="$TMP_DIR/escaped.tsv" PATH="$TMP_DIR/bin:$PATH" \
  "$ROOT_DIR/bin/exportctl.sh" run --jobs-config "$TMP_DIR/jobs.properties" \
  --env-config "$TMP_DIR/env.properties" --date 2026-03-17 default 2>&1 \
  >"$TMP_DIR/escaped_run.log"
assert_contains "[default] Export finished: file=./exports/default_2026-03-17.csv lines=3" \
  "$(cat "$TMP_DIR/escaped_run.log")" "escaping export keeps three rows"
assert_contains "[default] Completed successfully." \
  "$(cat "$TMP_DIR/escaped_run.log")" "escaping export succeeds"

escaped_file="$PROJECT_DIR/exports/default_2026-03-17.csv"
assert_file_eq "$escaped_file" $'1\tA\\tB\\nC|?E\\\\F\\0N\n2\t\n3\tplain\n' \
  "data escapes survive to the artifact and NULL is blanked"
assert_field_counts "$escaped_file" '2 2 2 ' "every exported row keeps its field count"
assert_eq "3" "$(awk 'END { print NR + 0 }' "$escaped_file")" "artifact has three lines"
rm -rf "$PROJECT_DIR/exports" "$PROJECT_DIR/exports_transfer"

###############################################################################
# Escaping under the production separators (|! and @#$ + LF): a data tab or LF
# must never touch the field separator or the line terminator
###############################################################################

printf '1\tA\\tB\\nC\\\\D|!E\n2\tNULL\n3\tplain\n' >"$TMP_DIR/pipes.tsv"
FAKE_MYSQL_TSV_FILE="$TMP_DIR/pipes.tsv" PATH="$TMP_DIR/bin:$PATH" \
  "$ROOT_DIR/bin/exportctl.sh" run --jobs-config "$TMP_DIR/jobs.properties" \
  --env-config "$TMP_DIR/env.properties" --date 2026-03-17 pipes 2>&1 \
  >"$TMP_DIR/pipes_run.log"
assert_contains "[pipes] Export finished: file=./exports/pipes_2026-03-17.csv lines=3" \
  "$(cat "$TMP_DIR/pipes_run.log")" "pipes export keeps three rows"

pipes_file="$PROJECT_DIR/exports/pipes_2026-03-17.csv"
# data tab -> \t, data LF -> \n, data backslash -> \\, data |! -> |?
assert_file_eq "$pipes_file" $'1|!A\\tB\\nC\\\\D|?E@#$\n2|!@#$\n3|!plain@#$\n' \
  "data escapes never reach the field separator or the line terminator"
assert_field_counts "$pipes_file" '2 2 2 ' \
  "every row keeps two fields under the |! separator" '\\|!'
assert_eq "3" "$(grep -o '@#[$]' "$pipes_file" | wc -l | tr -d ' ')" \
  "exactly one @#\$ terminator per row"
assert_eq "3" "$(awk 'END { print NR + 0 }' "$pipes_file")" \
  "data tabs and LFs do not add lines"
rm -rf "$PROJECT_DIR/exports" "$PROJECT_DIR/exports_transfer"

###############################################################################
# FILE_SPLIT run: draft lifecycle, stale cleanup, per-part transfer
###############################################################################

cat >"$TMP_DIR/split.properties" <<'EOF'
job.split.DB_TYPE=${ENV_TEST_DB_TYPE}
job.split.DB_HOST=${ENV_TEST_DB_HOST}
job.split.DB_PORT=${ENV_TEST_DB_PORT}
job.split.DB_NAME=${ENV_TEST_DB_NAME}
job.split.DB_USER=${ENV_TEST_DB_USER}
job.split.DB_PASSWORD_FILE=${ENV_TEST_DB_PASSWORD_FILE}
job.split.DB_PASSWORD_KEY_FILE=${ENV_TEST_DB_PASSWORD_KEY_FILE}
job.split.TABLE_NAME=users
job.split.COLUMNS=id,name
job.split.EXPORT_FILE=${ENV_EXPORT_ROOT}/${PART}-split_${EXPORT_DATE}.csv
job.split.FILE_SPLIT.ENABLED=true
job.split.FILE_SPLIT.MAX_SIZE=1
job.split.FILE_SPLIT.INDEX_WIDTH=2
job.split.COMPRESS.ENABLED=true
job.split.COMPRESS.MODE=gz
job.split.COMPRESS.OVERWRITE=true
job.split.COMPRESS.REMOVE_ORIGINAL=false
job.split.TRANSFER.ENABLED=true
job.split.TRANSFER.DIR=${ENV_TRANSFER_ROOT}
job.split.TRANSFER.MODE=copy
job.split.TRANSFER.OVERWRITE=true
job.split.TRANSFER.RENAME=${PART}-split_${EXPORT_DATE}.gz
job.splitfail.DB_TYPE=oracle
job.splitfail.DB_HOST=${ENV_TEST_DB_HOST}
job.splitfail.DB_PORT=${ENV_TEST_DB_PORT}
job.splitfail.DB_NAME=${ENV_TEST_DB_NAME}
job.splitfail.DB_USER=${ENV_TEST_DB_USER}
job.splitfail.DB_PASSWORD_FILE=${ENV_TEST_DB_PASSWORD_FILE}
job.splitfail.DB_PASSWORD_KEY_FILE=${ENV_TEST_DB_PASSWORD_KEY_FILE}
job.splitfail.TABLE_NAME=users
job.splitfail.COLUMNS=id,name
job.splitfail.EXPORT_FILE=${ENV_EXPORT_ROOT}/${PART}-splitfail_${EXPORT_DATE}.csv
job.splitfail.FILE_SPLIT.ENABLED=true
job.splitfail.FILE_SPLIT.MAX_SIZE=1G
job.splitfail.COMPRESS.ENABLED=true
job.splitfail.COMPRESS.MODE=gz
EOF

# FILE_SPLIT plan display: enabled jobs echo size/index_width/export_template.
split_plan_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" plan --jobs-config "$TMP_DIR/split.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 split splitfail 2>&1)"
assert_contains "FILE_SPLIT=size=1 index_width=2 export_template=./exports/\${PART}-split_2026-03-17.csv" "$split_plan_output" "plan prints enabled file split config"
assert_contains "FILE_SPLIT=size=1G index_width=2 export_template=./exports/\${PART}-splitfail_2026-03-17.csv" "$split_plan_output" "plan prints size suffix verbatim"

mkdir -p "$PROJECT_DIR/exports" "$PROJECT_DIR/exports_transfer"
# Stale parts from an earlier run: indices 02 and 09 must be removed, the
# transfer directory must be left alone.
printf 'stale\n' >"$PROJECT_DIR/exports/02-split_2026-03-17.csv"
printf 'stale\n' >"$PROJECT_DIR/exports/09-split_2026-03-17.csv"
printf 'stale\n' >"$PROJECT_DIR/exports_transfer/07-split_2026-03-17.gz"
split_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" run --jobs-config "$TMP_DIR/split.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 split 2>&1)"
assert_contains "[split] Completed successfully." "$split_output" "split job succeeds"
assert_contains "[split] Part ready: index=00" "$split_output" "split reports part 00"
assert_contains "[split] Part ready: index=01" "$split_output" "split reports part 01"
assert_contains "[split] Split finished: parts=2 lines=2" "$split_output" "split summary keeps line count and part count"
assert_contains "[split] Transferring part: index=00" "$split_output" "split transfers part 00"
assert_contains "[split] Transferring part: index=01" "$split_output" "split transfers part 01"
assert_contains "[split] Final artifact ready: file=./exports_transfer/00-split_2026-03-17.gz" "$split_output" "final artifact logged per part (00)"
assert_contains "[split] Final artifact ready: file=./exports_transfer/01-split_2026-03-17.gz" "$split_output" "final artifact logged per part (01)"
assert_contains "[split] Removed stale part: file=./exports/02-split_2026-03-17.csv" "$split_output" "stale part 02 removal logged"
assert_contains "[split] Removed stale part: file=./exports/09-split_2026-03-17.csv" "$split_output" "stale part 09 removal logged"

assert_eq "" "$(find "$PROJECT_DIR/exports" -maxdepth 1 -name '.file_split.*' -print)" "draft dir removed after success"
assert_true "[[ -f '$PROJECT_DIR/exports/00-split_2026-03-17.csv' ]]" "part 00 exists in export dir"
assert_true "[[ -f '$PROJECT_DIR/exports/01-split_2026-03-17.csv' ]]" "part 01 exists in export dir"
assert_true "[[ ! -e '$PROJECT_DIR/exports/02-split_2026-03-17.csv' ]]" "stale part 02 removed"
assert_true "[[ ! -e '$PROJECT_DIR/exports/09-split_2026-03-17.csv' ]]" "stale part 09 removed"
assert_true "[[ -f '$PROJECT_DIR/exports_transfer/00-split_2026-03-17.gz' ]]" "part 00 transferred"
assert_true "[[ -f '$PROJECT_DIR/exports_transfer/01-split_2026-03-17.gz' ]]" "part 01 transferred"
assert_true "[[ -f '$PROJECT_DIR/exports_transfer/07-split_2026-03-17.gz' ]]" "transfer directory left untouched"
split_joined="$(for part in 00 01; do gzip -cd "$PROJECT_DIR/exports/$part-split_2026-03-17.csv"; done)"
assert_eq $'1\tAlice|?A|?\n2\t' "$split_joined" "split parts preserve every row in order"

# Failure path: the draft must not survive a failed Pass 1 either.
mkdir -p "$PROJECT_DIR/exports"
splitfail_output="$(PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/bin/exportctl.sh" run --jobs-config "$TMP_DIR/split.properties" --env-config "$TMP_DIR/env.properties" --date 2026-03-17 splitfail 2>&1)"
assert_contains "[splitfail] Export failed." "$splitfail_output" "split failure is logged"
if [[ "$splitfail_output" == *'Completed successfully'* ]]; then
  echo "FAIL: failed split job does not report success" >&2
  exit 1
fi
assert_eq "" "$(find "$PROJECT_DIR/exports" -maxdepth 1 -name '.file_split.*' -print)" "draft dir removed after failure"
assert_true "[[ ! -e '$PROJECT_DIR/exports/00-splitfail_2026-03-17.csv' ]]" "failed split job produces no part"
rm -rf "$PROJECT_DIR/exports" "$PROJECT_DIR/exports_transfer"

if "$ROOT_DIR/bin/exportctl.sh" run >/dev/null 2>&1; then
  echo "FAIL: expected invalid args to exit non-zero" >&2
  exit 1
fi

if "$ROOT_DIR/bin/exportctl.sh" password encode >/dev/null 2>&1; then
  echo "FAIL: expected password command to exit non-zero" >&2
  exit 1
fi

echo "OK: exportctl_test.sh"
