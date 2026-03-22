#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/properties.sh"

render_select_columns() {
  local plan_name="$1"
  local -n _plan="$plan_name"
  local item col split_line split_col split_size split_chunks
  local -a raw_columns=()
  local -a rendered=()
  declare -A split_size_map=()
  declare -A split_chunk_map=()
  local i start

  if [[ -n "${_plan[splits]:-}" && "${_plan[db_type]:-}" == "mysql" ]]; then
    while IFS= read -r split_line; do
      [[ -z "$split_line" ]] && continue
      IFS='|' read -r split_col split_size split_chunks <<<"$split_line"
      split_size_map["$split_col"]="$split_size"
      split_chunk_map["$split_col"]="$split_chunks"
    done <<<"${_plan[splits]}"
  fi

  IFS=',' read -r -a raw_columns <<<"${_plan[columns]}"
  for item in "${raw_columns[@]}"; do
    col="$(trim "$item")"
    [[ -z "$col" ]] && continue
    if [[ -n "${split_size_map[$col]:-}" && -n "${split_chunk_map[$col]:-}" ]]; then
      for ((i = 1; i <= split_chunk_map[$col]; i++)); do
        start=$(((i - 1) * split_size_map[$col] + 1))
        rendered+=("SUBSTRING(${col}, ${start}, ${split_size_map[$col]}) AS ${col}_part${i}")
      done
    else
      rendered+=("$col")
    fi
  done

  printf '%s' "$(IFS=,; echo "${rendered[*]}")"
}

render_where_clause() {
  local plan_name="$1"
  local -n _plan="$plan_name"
  if [[ -n "${_plan[where_raw]:-}" ]]; then
    printf ' WHERE %s' "${_plan[where_raw]}"
  fi
}

render_select_sql() {
  local plan_name="$1"
  local -n _plan="$plan_name"
  printf 'SELECT %s FROM %s%s' \
    "$(render_select_columns "$plan_name")" \
    "${_plan[table]}" \
    "$(render_where_clause "$plan_name")"
}
