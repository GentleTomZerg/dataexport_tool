#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This library requires bash." >&2
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail
shopt -s extglob

_sql_trim() {
  local s="$1"
  s="${s##+([[:space:]])}"
  s="${s%%+([[:space:]])}"
  printf '%s' "$s"
}

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
    col="$(_sql_trim "$item")"
    [[ -z "$col" ]] && continue
    columns+=("$col")
  done

  if [[ ${DATA_SPLITS+set} && "$db_type" == "mysql" ]]; then
    declare -A split_size split_chunks
    local split_item split_col size chunks
    for split_item in "${DATA_SPLITS[@]}"; do
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

## Build a SELECT SQL from DATA_TABLE, DATA_COLUMNS, DATA_FILTERS.
##
## Expected DATA_FILTERS format (built by lib/job_config.sh):
##   Each entry is a pipe-separated string:
##     - "col|op|value"               (single value)
##     - "col|BETWEEN|from|to"        (range)
##
## Supported operators:
##   - any operator passed through as-is (e.g. =, !=, <, <=, >, >=, LIKE)
##   - BETWEEN with from/to
##
## Behavior:
##   - Values are always single-quoted and escaped for single quotes.
##   - Filters are combined with AND.
##
## Usage: sql="$(build_select_sql)"
build_select_sql() {
  local select_cols
  select_cols="$(_sql_build_select_columns "$DATA_COLUMNS")"
  local sql="SELECT ${select_cols} FROM ${DATA_TABLE}"
  local where_parts=()
  local item col op v1 v2 esc

  if [[ ${DATA_FILTERS+set} ]]; then
    for item in "${DATA_FILTERS[@]}"; do
      IFS='|' read -r col op v1 v2 <<<"$item"
      if [[ "${op^^}" == "BETWEEN" ]]; then
        # Format: col|BETWEEN|from|to
        esc="$(sql_escape_literal "$v1")"
        v2="$(sql_escape_literal "$v2")"
        where_parts+=("${col} BETWEEN '${esc}' AND '${v2}'")
      else
        # Format: col|op|value (op defaults to '=' in job_config)
        esc="$(sql_escape_literal "$v1")"
        where_parts+=("${col} ${op} '${esc}'")
      fi
    done
  fi

  if [[ "${#where_parts[@]}" -gt 0 ]]; then
    local i joined=""
    for i in "${!where_parts[@]}"; do
      if [[ -n "$joined" ]]; then
        joined+=" AND "
      fi
      joined+="${where_parts[$i]}"
    done
    sql+=" WHERE ${joined}"
  fi

  printf '%s' "$sql"
}
