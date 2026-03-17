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
## Usage: sql="$(build_select_sql)"
build_select_sql() {
  local sql="SELECT ${DATA_COLUMNS} FROM ${DATA_TABLE}"
  local where_parts=()
  local item col op v1 v2 esc

  for item in "${DATA_FILTERS[@]:-}"; do
    IFS='|' read -r col op v1 v2 <<<"$item"
    if [[ "${op^^}" == "BETWEEN" ]]; then
      esc="$(sql_escape_literal "$v1")"
      v2="$(sql_escape_literal "$v2")"
      where_parts+=("${col} BETWEEN '${esc}' AND '${v2}'")
    else
      esc="$(sql_escape_literal "$v1")"
      where_parts+=("${col} ${op} '${esc}'")
    fi
  done

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
