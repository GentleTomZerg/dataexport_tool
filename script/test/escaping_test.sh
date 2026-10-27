#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/exportctl/run/db.sh"

###############################################################################
# Field data escaping (docs/adr/0002-field-data-is-escaped.md)
#
# Input to `_sanitize_fields` is DB client output: real tabs between fields, real
# LFs between rows, and NUL/tab/LF/backslash already escaped by the client (mysql
# --batch without --raw). A field's data must never contain a raw tab or LF, so a
# row stays one line with a fixed field count whatever the data.
###############################################################################

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUT_FILE="$TMP_DIR/out"

# Run the two transform passes over client-shaped input, with optional
# separator/terminator/replacement overrides.
transform_to_file() {
  local input="$1"
  local field_sep="${2:-\t}"
  local line_term="${3:-\n}"
  local replacement="${4:-|?}"

  printf '%s' "$input" |
    _sanitize_fields "$replacement" |
    _apply_separators "$field_sep" "$line_term" >"$OUT_FILE"
}

# Assert the bytes of OUT_FILE. The trailing sentinel keeps command substitution
# from swallowing a final newline.
assert_output_eq() {
  local expected="$1"
  local msg="$2"
  local actual
  actual="$(cat "$OUT_FILE"; printf 'sentinel')"
  assert_eq "${expected}sentinel" "$actual" "$msg"
}

assert_every_line_has_fields() {
  local expected="$1"
  local msg="$2"
  local actual
  actual="$(awk -F'\t' '{ printf "%d ", NF }' "$OUT_FILE")"
  assert_eq "$expected" "$actual" "$msg"
}

###############################################################################
# A tab in data is the two bytes \ t -- never a field separator
###############################################################################

# `\t` as produced by mysql --batch for a tab in a value.
transform_to_file $'1\tA\\tB\n'
assert_output_eq $'1\tA\\tB\n' "data tab survives as the two bytes backslash-t"

transform_to_file $'1\tA\\tB\n' '|!' '@#$\n'
assert_output_eq $'1|!A\\tB@#$\n' "data tab survives under custom separators"

# A tab in data must not grow the field count: two fields in, two fields out.
transform_to_file $'1\tA\\tB\n'
assert_every_line_has_fields '2 ' 'data tab does not add a field'

transform_to_file $'1\tA\\tB\\tC\n'
assert_every_line_has_fields '2 ' 'several data tabs do not add fields'

###############################################################################
# The rest of the escaped set passes through untouched
###############################################################################

transform_to_file $'1\tA\\nB\n'
assert_output_eq $'1\tA\\nB\n' "data newline stays the two bytes backslash-n"

transform_to_file $'1\tA\\rB\n'
assert_output_eq $'1\tA\\rB\n' "already escaped CR stays as two bytes"

transform_to_file $'1\tA\\0B\n'
assert_output_eq $'1\tA\\0B\n' "escaped NUL stays as two bytes"

# A backslash in data reaches this stage already doubled by the client, and must
# not be doubled again.
transform_to_file $'1\tA\\\\B\n'
assert_output_eq $'1\tA\\\\B\n' "doubled backslash is not escaped twice"

# Data that literally contains the two characters \ t reaches this stage as
# \\t (client-doubled) and must stay that way, so that unescaping \ -> \ and
# \t -> tab round-trips.
transform_to_file $'1\tA\\\\tB\n'
assert_output_eq $'1\tA\\\\tB\n' "literal backslash-t in data is preserved for unescaping"

###############################################################################
# Known limitation: mysql --batch writes CR raw, so a raw CR is passed through
# unchanged. It is harmless to the structure -- CR is neither the field separator
# nor the record separator -- but it is not escaped the way postgres escapes it.
###############################################################################

transform_to_file $'1\tA\rB\n'
assert_output_eq $'1\tA\rB\n' "raw CR is passed through unchanged (known limitation)"

transform_to_file $'1\tA\r\n'
assert_every_line_has_fields '2 ' 'raw CR does not add a field'
assert_eq "1" "$(awk 'END { print NR + 0 }' "$OUT_FILE")" 'raw CR does not split the row'

###############################################################################
# Existing data munging keeps working, on escaped text
###############################################################################

transform_to_file $'1\tAlice|!A|!\n'
assert_output_eq $'1\tAlice|?A|?\n' "separator collision is replaced with the default |?"

transform_to_file $'1\tAlice|!A|!\n' '\t' '\n' '|X'
assert_output_eq $'1\tAlice|XA|X\n' "separator collision uses the configured replacement"

transform_to_file $'1\tNULL\n'
assert_output_eq $'1\t\n' "NULL becomes an empty field"

transform_to_file $'1\t\\N\n'
assert_output_eq $'1\t\\N\n' "postgres NULL marker \\N is not treated as NULL"

transform_to_file $'1\t2\t\n'
assert_output_eq $'1\t2\t\n' "a trailing empty field is preserved"

###############################################################################
# Combinations: one field carrying every hazard at once
###############################################################################

transform_to_file $'1\tA\\tB\rC\\nD|!E\\\\F\n'
assert_output_eq $'1\tA\\tB\rC\\nD|?E\\\\F\n' "all hazards in one field are handled independently"
assert_every_line_has_fields '2 ' "all hazards in one field keep the field count"

###############################################################################
# Row structure survives: one row in, one line out
###############################################################################

transform_to_file $'1\tA\\tB\n2\tC\rD\n3\tE|!F\n'
assert_output_eq $'1\tA\\tB\n2\tC\rD\n3\tE|?F\n' "three rows each stay one line"
assert_every_line_has_fields '2 2 2 ' "three rows each keep two fields"

line_count="$(awk 'END { print NR + 0 }' "$OUT_FILE")"
assert_eq "3" "$line_count" "row count is preserved"

# An empty result stays an empty file.
transform_to_file ''
assert_eq "" "$(cat "$OUT_FILE")" "empty input stays empty"

echo "OK: escaping_test"
