#!/usr/bin/env bash

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

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: $msg" >&2
    echo "  expected to contain: [$needle]" >&2
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

# Assert the exact bytes of a file. The trailing sentinel keeps command
# substitution from swallowing a final newline.
assert_file_eq() {
  local file="$1"
  local expected="$2"
  local msg="$3"
  local actual
  actual="$(cat "$file"; printf 'sentinel')"
  assert_eq "${expected}sentinel" "$actual" "$msg"
}

# Assert the per-line field counts of a delimited file as a space-separated
# sequence, e.g. "2 2 2 " for three well-formed rows. The optional fourth
# argument is the awk field separator regex; it defaults to a real tab.
assert_field_counts() {
  local file="$1"
  local expected="$2"
  local msg="$3"
  local fs="${4:-\t}"
  assert_eq "$expected" "$(awk -F"$fs" '{ printf "%d ", NF }' "$file")" "$msg"
}
