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
