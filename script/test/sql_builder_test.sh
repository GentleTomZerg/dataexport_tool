#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/sql_builder.sh"

# Base data used by all tests.
declare -Ag JOB
JOB[table]="users"
JOB[columns]="id,name,email"

# 1) No WHERE clause.
JOB[where]=""
assert_eq "SELECT id,name,email FROM users" "$(build_select_sql)" "no where"

# 2) Simple WHERE clause.
JOB[where]="status = 'active'"
assert_eq "SELECT id,name,email FROM users WHERE status = 'active'" "$(build_select_sql)" "simple where"

# 3) Complex WHERE clause with AND.
JOB[where]="status = 'active' AND age >= 18"
assert_eq "SELECT id,name,email FROM users WHERE status = 'active' AND age >= 18" "$(build_select_sql)" "multiple conditions"

# 4) BETWEEN in WHERE.
JOB[where]="created_at BETWEEN '2024-01-01' AND '2024-01-31'"
assert_eq "SELECT id,name,email FROM users WHERE created_at BETWEEN '2024-01-01' AND '2024-01-31'" "$(build_select_sql)" "between where"

# 5) LIKE in WHERE.
JOB[where]="name LIKE '%bob%'"
assert_eq "SELECT id,name,email FROM users WHERE name LIKE '%bob%'" "$(build_select_sql)" "like where"

# 6) Single-quote in WHERE (user responsibility to escape).
JOB[where]="note = 'O''Brien'"
assert_eq "SELECT id,name,email FROM users WHERE note = 'O''Brien'" "$(build_select_sql)" "escaped quote where"

# 7) WHERE with OR and IN.
JOB[where]="status IN ('active', 'pending') OR region = 'US'"
assert_eq "SELECT id,name,email FROM users WHERE status IN ('active', 'pending') OR region = 'US'" "$(build_select_sql)" "or and in where"

# 8) Split columns with WHERE: splits affect SELECT, WHERE is passed through.
DB_TYPE="mysql"
JOB[columns]="id,content,email"
JOB[where]="created_at > '2024-01-01'"
JOB_SPLITS=("content|4|3")
assert_eq "SELECT id,SUBSTRING(content, 1, 4) AS content_part1,SUBSTRING(content, 5, 4) AS content_part2,SUBSTRING(content, 9, 4) AS content_part3,email FROM users WHERE created_at > '2024-01-01'" "$(build_select_sql)" "split with where"

# 9) Split columns without WHERE.
JOB[where]=""
assert_eq "SELECT id,SUBSTRING(content, 1, 4) AS content_part1,SUBSTRING(content, 5, 4) AS content_part2,SUBSTRING(content, 9, 4) AS content_part3,email FROM users" "$(build_select_sql)" "split no where"

echo "OK: sql_builder_test.sh"
