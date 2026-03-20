#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This library requires bash." >&2
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail
shopt -s extglob

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_LIB_DIR/common.sh"
unset _LIB_DIR

sql_escape_literal() {
  local s="$1"
  s="${s//\'/\'\'}"
  printf '%s' "$s"
}

_sql_build_select_columns() {
  local columns_raw="$1"
  local db_type="${DB_TYPE:-mysql}"
  local raw_columns=()
  local columns=()
  local item col

  IFS=',' read -r -a raw_columns <<<"$columns_raw"
  for item in "${raw_columns[@]}"; do
    col="$(trim "$item")"
    [[ -z "$col" ]] && continue
    columns+=("$col")
  done

  if [[ ${JOB_SPLITS+set} && "$db_type" == "mysql" ]]; then
    declare -A split_size split_chunks
    local split_item split_col size chunks
    for split_item in "${JOB_SPLITS[@]}"; do
      IFS='|' read -r split_col size chunks <<<"$split_item"
      split_size["$split_col"]="$size"
      split_chunks["$split_col"]="$chunks"
    done

    local final_cols=()
    local i start size_val chunks_val
    for col in "${columns[@]}"; do
      size_val="${split_size[$col]:-}"
      chunks_val="${split_chunks[$col]:-}"
      if [[ -n "$size_val" && -n "$chunks_val" ]]; then
        for ((i = 1; i <= chunks_val; i++)); do
          start=$(((i - 1) * size_val + 1))
          final_cols+=("SUBSTRING(${col}, ${start}, ${size_val}) AS ${col}_part${i}")
        done
      else
        final_cols+=("$col")
      fi
    done
    printf '%s' "$(IFS=,; echo "${final_cols[*]}")"
    return
  fi

  printf '%s' "$(IFS=,; echo "${columns[*]}")"
}

## Build a SELECT SQL from JOB[table], JOB[columns], JOB[where].
##
## If JOB[where] is set, it is used as the WHERE clause directly.
## Otherwise no WHERE clause is added.
##
## Splits are applied to the SELECT columns regardless of WHERE source.
##
## Usage: sql="$(build_select_sql)"
build_select_sql() {
  local select_cols
  select_cols="$(_sql_build_select_columns "${JOB[columns]}")"
  local sql="SELECT ${select_cols} FROM ${JOB[table]}"

  if [[ -n "${JOB[where]:-}" ]]; then
    sql+=" WHERE ${JOB[where]}"
  fi

  printf '%s' "$sql"
}
