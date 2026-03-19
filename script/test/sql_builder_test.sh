#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/sql_builder.sh"

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

# Base data used by all tests.
JOB_TABLE="users"
JOB_COLUMNS="id,name,email"

# 1) No filters.
JOB_FILTERS=()
assert_eq "SELECT id,name,email FROM users" "$(build_select_sql)" "no filters"

# 2) Single equality.
JOB_FILTERS=("status|=|active")
assert_eq "SELECT id,name,email FROM users WHERE status = 'active'" "$(build_select_sql)" "single equals"

# 3) Multiple filters ANDed.
JOB_FILTERS=("status|=|active" "age|>=|18")
assert_eq "SELECT id,name,email FROM users WHERE status = 'active' AND age >= '18'" "$(build_select_sql)" "multiple filters"

# 4) LIKE operator.
JOB_FILTERS=("name|LIKE|%bob%")
assert_eq "SELECT id,name,email FROM users WHERE name LIKE '%bob%'" "$(build_select_sql)" "like operator"

# 5) BETWEEN range.
JOB_FILTERS=("created_at|BETWEEN|2024-01-01|2024-01-31")
assert_eq "SELECT id,name,email FROM users WHERE created_at BETWEEN '2024-01-01' AND '2024-01-31'" "$(build_select_sql)" "between operator"

# 6) Single-quote escaping.
JOB_FILTERS=("note|=|O'Brien")
assert_eq "SELECT id,name,email FROM users WHERE note = 'O''Brien'" "$(build_select_sql)" "escape single quote"

# 7) Mixed operators with BETWEEN.
JOB_FILTERS=("status|=|active" "created_at|BETWEEN|2024-01-01|2024-01-31" "score|>|10")
assert_eq "SELECT id,name,email FROM users WHERE status = 'active' AND created_at BETWEEN '2024-01-01' AND '2024-01-31' AND score > '10'" "$(build_select_sql)" "mixed operators"

# 8) Split columns (mysql only): remove original and add chunked pieces.
DB_TYPE="mysql"
JOB_COLUMNS="id,content,email"
JOB_FILTERS=()
JOB_SPLITS=("content|4|3")
assert_eq "SELECT id,SUBSTRING(content, 1, 4) AS content_part1,SUBSTRING(content, 5, 4) AS content_part2,SUBSTRING(content, 9, 4) AS content_part3,email FROM users" "$(build_select_sql)" "split columns"

echo "OK: sql_builder_test.sh"
