#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/export/job.sh"

_selector_has_group() {
  local groups_raw="$1"
  local wanted="$2"
  local item
  local -a groups=()
  IFS=',' read -r -a groups <<<"$groups_raw"
  for item in "${groups[@]}"; do
    item="$(trim "$item")"
    [[ "$item" == "$wanted" ]] && return 0
  done
  return 1
}

resolve_job_selectors() {
  local props_name="$1"
  local selectors_name="$2"
  local out_name="$3"
  local -n _selectors="$selectors_name"
  local -n _out="$out_name"
  local selector job_name group_name
  local -a all_jobs=()
  declare -A selected=()
  declare -A known=()
  local -A job=()

  mapfile -t all_jobs < <(list_export_jobs "$props_name")
  for job_name in "${all_jobs[@]}"; do
    known["$job_name"]=1
  done

  if [[ "${#_selectors[@]}" -eq 0 ]]; then
    _out=("${all_jobs[@]}")
    return 0
  fi

  for selector in "${_selectors[@]}"; do
    if [[ "$selector" == group:* ]]; then
      group_name="${selector#group:}"
      for job_name in "${all_jobs[@]}"; do
        if load_export_job "$props_name" "$job_name" job && _selector_has_group "${job[groups]}" "$group_name"; then
          selected["$job_name"]=1
        fi
      done
    elif [[ -n "${known[$selector]:-}" ]]; then
      selected["$selector"]=1
    else
      printf 'ERROR: unknown selector %s\n' "$selector" >&2
    fi
  done

  _out=()
  for job_name in "${!selected[@]}"; do
    _out+=("$job_name")
  done
  if [[ "${#_out[@]}" -gt 0 ]]; then
    mapfile -t _out < <(printf '%s\n' "${_out[@]}" | sort)
  fi
}
