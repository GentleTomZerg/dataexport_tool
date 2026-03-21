#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/export/job.sh"

resolve_job_selectors() {
  local props_name="$1"
  local selectors_name="$2"
  local out_name="$3"
  local -n _selectors="$selectors_name"
  local -n _out="$out_name"
  local selector job_name
  local -a all_jobs=()
  declare -A selected=()
  declare -A known=()

  mapfile -t all_jobs < <(list_export_jobs "$props_name")
  for job_name in "${all_jobs[@]}"; do
    known["$job_name"]=1
  done

  if [[ "${#_selectors[@]}" -eq 0 ]]; then
    _out=("${all_jobs[@]}")
    return 0
  fi

  for selector in "${_selectors[@]}"; do
    if [[ -n "${known[$selector]:-}" ]]; then
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
