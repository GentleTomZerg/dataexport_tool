#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This library requires bash." >&2
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

sql_escape_literal() {
  local s="$1"
  s="${s//\'/\'\'}"
  printf "%s" "$s"
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
  local sql="SELECT ${DATA_COLUMNS} FROM ${DATA_TABLE}"
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
