#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/exportctl/run/split.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

EXPORT_DATE="2026-03-17"
PARTS_DIR="$TMP_DIR/parts"

# --- fixtures ---------------------------------------------------------------

# Deterministic pseudo-random bytes: incompressible enough that gzip cannot
# shrink a part below MAX_SIZE, which exercises the re-split path.
random_stream() {
  local bytes="$1"
  local seed="$2"
  LC_ALL=C awk -v bytes="$bytes" -v seed="$seed" 'BEGIN {
    srand(seed)
    for (i = 0; i < bytes; i++) {
      printf "%c", 33 + int(rand() * 94)
    }
  }'
}

write_csv() {
  local file="$1"
  local content="$2"
  printf '%s' "$content" >"$file"
}

# A header plus $rows pseudo-random data lines, incompressible enough that a
# 3xMAX_SIZE first part overflows and exercises the re-split path.
write_incompressible_csv() {
  local file="$1"
  local rows="$2"
  local seed="$3"

  {
    printf 'id,payload\n'
    LC_ALL=C awk -v n="$rows" -v seed="$seed" 'BEGIN {
      srand(seed)
      for (i = 1; i <= n; i++) {
        printf "%d,", i
        for (j = 0; j < 40; j++) printf "%c", 33 + int(rand() * 94)
        printf "\n"
      }
    }'
  } >"$file"
}

make_plan() {
  local plan_name="$1"
  local template="$2"
  local max_size="$3"
  local index_width="$4"
  local -n _plan="$plan_name"

  _plan=()
  _plan[job_name]="users"
  _plan[export_file]="$template"
  _plan[file_split_max_size]="$max_size"
  _plan[file_split_index_width]="$index_width"
}

# Run the file split and expose the resulting records in PART_RECORDS.
run_split() {
  local plan_name="$1"
  local csv="$2"
  local -n _plan="$plan_name"

  split_and_compress_parts "$csv" "$plan_name" || return 1
  PART_RECORDS=()
  if [[ -n "${_plan[parts]:-}" ]]; then
    while IFS= read -r rec; do
      PART_RECORDS+=("$rec")
    done < <(printf '%s\n' "${_plan[parts]}")
  fi
}

assert_roundtrip() {
  local csv="$1"
  local label="$2"
  local joined="$TMP_DIR/joined"
  local rec gz

  : >"$joined"
  for rec in "${PART_RECORDS[@]}"; do
    gz="${rec##*|}"
    gzip -cd "$gz" >>"$joined" || {
      printf 'FAIL: %s: part is not valid gzip: %s\n' "$label" "$gz" >&2
      exit 1
    }
  done

  if ! cmp -s "$csv" "$joined"; then
    printf 'FAIL: %s: joined parts differ from source CSV\n' "$label" >&2
    exit 1
  fi
}

# Assert per-part invariants: byte and line accounting, gz limit, line boundary.
assert_part_invariants() {
  local max_bytes="$1"
  local label="$2"
  local rec index lines bytes_csv bytes_gz gz decoded_bytes decoded_lines last_byte

  for rec in "${PART_RECORDS[@]}"; do
    IFS='|' read -r index lines bytes_csv bytes_gz gz <<<"$rec"

    decoded_bytes="$(gzip -cd "$gz" | wc -c | tr -d '[:space:]')"
    assert_eq "$bytes_csv" "$decoded_bytes" "$label part $index uncompressed bytes match"

    decoded_lines="$(gzip -cd "$gz" | awk 'END { print NR + 0 }')"
    assert_eq "$lines" "$decoded_lines" "$label part $index line count matches"

    if (( bytes_gz > max_bytes )) && (( lines != 1 )); then
      printf 'FAIL: %s: part %s exceeds MAX_SIZE with %s lines\n' "$label" "$index" "$lines" >&2
      exit 1
    fi

    if (( lines > 0 )); then
      last_byte="$(gzip -cd "$gz" | tail -c 1 | od -An -tu1 | tr -d '[:space:]')"
      assert_eq "10" "$last_byte" "$label part $index ends on a line boundary"
    fi
  done
}

assert_sums() {
  local csv="$1"
  local label="$2"
  local total_bytes total_lines rec index lines bytes_csv bytes_gz gz
  local sum_csv=0 sum_lines=0

  total_bytes="$(wc -c <"$csv" | tr -d '[:space:]')"
  total_lines="$(awk 'END { print NR + 0 }' "$csv")"

  for rec in "${PART_RECORDS[@]}"; do
    IFS='|' read -r index lines bytes_csv bytes_gz gz <<<"$rec"
    sum_csv=$((sum_csv + bytes_csv))
    sum_lines=$((sum_lines + lines))
  done

  assert_eq "$total_bytes" "$sum_csv" "$label sum of part bytes equals source bytes"
  assert_eq "$total_lines" "$sum_lines" "$label sum of part lines equals source lines"
}

# Parts are numbered from 00 with no gaps, in output order.
assert_indexes_contiguous() {
  local label="$1"
  local expected=0 rec index lines bytes_csv bytes_gz gz

  for rec in "${PART_RECORDS[@]}"; do
    IFS='|' read -r index lines bytes_csv bytes_gz gz <<<"$rec"
    assert_eq "$expected" "$index" "$label part index $expected"
    expected=$((expected + 1))
  done
}

###############################################################################
# Exactly one part
###############################################################################

ONE_CSV="$TMP_DIR/one.csv"
write_csv "$ONE_CSV" 'id,name
1,alice
2,bob
3,carol
'

declare -A ONE_PLAN=()
make_plan ONE_PLAN "$PARTS_DIR/\${PART}-users-\${EXPORT_DATE}.csv" 1M 2
run_split ONE_PLAN "$ONE_CSV"
assert_eq "1" "${ONE_PLAN[part_count]}" "single part: part count"
assert_eq "1" "${#PART_RECORDS[@]}" "single part: one record"
IFS='|' read -r ONE_INDEX ONE_LINES ONE_CSV_BYTES ONE_GZ_BYTES ONE_GZ <<<"${PART_RECORDS[0]}"
assert_eq "0" "$ONE_INDEX" "single part: index 00"
assert_eq "4" "$ONE_LINES" "single part: all four lines"
assert_eq "30" "$ONE_CSV_BYTES" "single part: uncompressed bytes"
assert_contains "00-users-2026-03-17.csv" "${PART_RECORDS[0]}" "single part: rendered part name"
assert_part_invariants 1048576 "single part"
assert_roundtrip "$ONE_CSV" "single part"
assert_sums "$ONE_CSV" "single part"

###############################################################################
# Multiple parts
###############################################################################

MULTI_CSV="$TMP_DIR/multi.csv"
{
  printf 'id,payload\n'
  awk 'BEGIN {
    for (i = 1; i <= 400; i++) {
      printf "%d,", i
      for (j = 0; j < 60; j++) printf "%c", 65 + (i + j) % 26
      printf "\n"
    }
  }'
} >"$MULTI_CSV"

declare -A MULTI_PLAN=()
make_plan MULTI_PLAN "$PARTS_DIR/\${PART}-users-\${EXPORT_DATE}.csv" 512 2
run_split MULTI_PLAN "$MULTI_CSV"
if (( MULTI_PLAN[part_count] < 2 )); then
  printf 'FAIL: multiple parts: expected at least 2 parts, got %s\n' "${MULTI_PLAN[part_count]}" >&2
  exit 1
fi
if (( MULTI_PLAN[part_count] >= 20 )); then
  printf 'FAIL: multiple parts: packing regressed, got %s parts\n' "${MULTI_PLAN[part_count]}" >&2
  exit 1
fi
assert_eq "${MULTI_PLAN[part_count]}" "${#PART_RECORDS[@]}" "multiple parts: record count matches"
assert_indexes_contiguous "multiple parts"
assert_contains "00-users-2026-03-17.csv" "${PART_RECORDS[0]}" "multiple parts: first index is 00"
assert_contains "01-users-2026-03-17.csv" "${PART_RECORDS[1]}" "multiple parts: second index is 01"
assert_part_invariants 512 "multiple parts"
assert_roundtrip "$MULTI_CSV" "multiple parts"
assert_sums "$MULTI_CSV" "multiple parts"

###############################################################################
# Single line larger than MAX_SIZE (must never be cut mid-line)
###############################################################################

LONG_CSV="$TMP_DIR/long.csv"
{
  printf '%s\n' "$(random_stream 4096 7)"
  printf 'tail-a\ntail-b\n'
} >"$LONG_CSV"

declare -A LONG_PLAN=()
make_plan LONG_PLAN "$PARTS_DIR/\${PART}-long-\${EXPORT_DATE}.csv" 200 2
run_split LONG_PLAN "$LONG_CSV"
IFS='|' read -r LONG_INDEX LONG_LINES LONG_CSV_BYTES LONG_GZ_BYTES LONG_GZ <<<"${PART_RECORDS[0]}"
assert_eq "1" "$LONG_LINES" "oversized line: first part holds exactly one line"
if (( LONG_GZ_BYTES <= 200 )); then
  printf 'FAIL: oversized line: expected gz over MAX_SIZE, got %s\n' "$LONG_GZ_BYTES" >&2
  exit 1
fi
assert_contains "00-long-2026-03-17.csv" "${PART_RECORDS[0]}" "oversized line: part name"
assert_part_invariants 200 "oversized line"
assert_roundtrip "$LONG_CSV" "oversized line"
assert_sums "$LONG_CSV" "oversized line"

###############################################################################
# Source without a trailing newline round-trips byte for byte
###############################################################################

NOEOL_CSV="$TMP_DIR/noeol.csv"
printf 'id,name\n1,alice\n2,bob' >"$NOEOL_CSV"

declare -A NOEOL_PLAN=()
make_plan NOEOL_PLAN "$PARTS_DIR/\${PART}-noeol-\${EXPORT_DATE}.csv" 1M 2
run_split NOEOL_PLAN "$NOEOL_CSV"
assert_eq "1" "${NOEOL_PLAN[part_count]}" "no trailing newline: one part"
assert_roundtrip "$NOEOL_CSV" "no trailing newline"
assert_sums "$NOEOL_CSV" "no trailing newline"

###############################################################################
# Empty input
###############################################################################

EMPTY_CSV="$TMP_DIR/empty.csv"
: >"$EMPTY_CSV"

declare -A EMPTY_PLAN=()
make_plan EMPTY_PLAN "$PARTS_DIR/\${PART}-empty-\${EXPORT_DATE}.csv" 1K 2
run_split EMPTY_PLAN "$EMPTY_CSV"
assert_eq "1" "${EMPTY_PLAN[part_count]}" "empty input: one part"
assert_eq "1" "${#PART_RECORDS[@]}" "empty input: one record"
IFS='|' read -r EMPTY_INDEX EMPTY_LINES EMPTY_CSV_BYTES EMPTY_GZ_BYTES EMPTY_GZ <<<"${PART_RECORDS[0]}"
assert_eq "0" "$EMPTY_INDEX" "empty input: index 00"
assert_eq "0" "$EMPTY_LINES" "empty input: zero lines"
assert_eq "0" "$EMPTY_CSV_BYTES" "empty input: zero csv bytes"
assert_contains "00-empty-2026-03-17.csv" "${PART_RECORDS[0]}" "empty input: part name"
assert_eq "" "$(gzip -cd "$EMPTY_GZ")" "empty input: gz decompresses to nothing"

###############################################################################
# Incompressible data triggers the re-split path and keeps every part in budget
###############################################################################

HARD_CSV="$TMP_DIR/hard.csv"
write_incompressible_csv "$HARD_CSV" 120 99

declare -A HARD_PLAN=()
make_plan HARD_PLAN "$PARTS_DIR/\${PART}-hard-\${EXPORT_DATE}.csv" 400 2
run_split HARD_PLAN "$HARD_CSV"
if (( HARD_PLAN[part_count] < 2 )); then
  printf 'FAIL: hard data: expected multiple parts, got %s\n' "${HARD_PLAN[part_count]}" >&2
  exit 1
fi
assert_indexes_contiguous "hard data"
assert_part_invariants 400 "hard data"
assert_roundtrip "$HARD_CSV" "hard data"
assert_sums "$HARD_CSV" "hard data"

###############################################################################
# Index overflow aborts with a helpful error
###############################################################################

OVERFLOW_CSV="$TMP_DIR/overflow.csv"
write_incompressible_csv "$OVERFLOW_CSV" 80 5

declare -A OVERFLOW_PLAN=()
make_plan OVERFLOW_PLAN "$PARTS_DIR/\${PART}-overflow-\${EXPORT_DATE}.csv" 100 1
if err="$(split_and_compress_parts "$OVERFLOW_CSV" OVERFLOW_PLAN 2>&1 >/dev/null)"; then
  echo "FAIL: index overflow: expected failure" >&2
  exit 1
fi
assert_contains "INDEX_WIDTH" "$err" "index overflow mentions INDEX_WIDTH"

echo "OK: split_test.sh"
