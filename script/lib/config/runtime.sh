#!/usr/bin/env bash

init_runtime_context() {
  local run_date="$1"
  local out_name="$2"
  local -n _out="$out_name"
  local epoch month_start next_month_epoch next_month_first

  if [[ -z "$run_date" ]]; then
    run_date="$(date +%F)"
  fi

  _out[export_date]="$run_date"
  _out[today]="$run_date"

  if [[ "$(uname)" == "Darwin" ]]; then
    epoch="$(date -j -f "%Y-%m-%d" "$run_date" "+%s")"
    _out[yesterday]="$(date -r $((epoch - 86400)) "+%F")"
    _out[export_month]="$(date -r "$epoch" "+%Y-%m")"
    month_start="$(date -r "$epoch" "+%Y-%m-01")"
    _out[month_start]="$month_start"
    next_month_epoch="$(date -j -f "%Y-%m-%d" "$month_start" "+%s")"
    next_month_epoch=$((next_month_epoch + 32 * 86400))
    next_month_first="$(date -r "$next_month_epoch" "+%Y-%m-01")"
    _out[month_end]="$(date -r $(($(date -j -f "%Y-%m-%d" "$next_month_first" "+%s") - 86400)) "+%F")"
  else
    _out[yesterday]="$(date -d "$run_date -1 day" +%F)"
    _out[export_month]="$(date -d "$run_date" +%Y-%m)"
    _out[month_start]="$(date -d "$run_date" +%Y-%m-01)"
    _out[month_end]="$(date -d "${_out[month_start]} +1 month -1 day" +%F)"
  fi

  export EXPORT_DATE="${_out[export_date]}"
  export TODAY="${_out[today]}"
  export YESTERDAY="${_out[yesterday]}"
  export EXPORT_MONTH="${_out[export_month]}"
  export MONTH_START="${_out[month_start]}"
  export MONTH_END="${_out[month_end]}"
}

print_runtime_context() {
  local runtime_name="$1"
  local -n _runtime="$runtime_name"
  printf '== Runtime ==\n'
  printf 'EXPORT_DATE=%s\n' "${_runtime[export_date]}"
  printf 'TODAY=%s\n' "${_runtime[today]}"
  printf 'YESTERDAY=%s\n' "${_runtime[yesterday]}"
  printf 'EXPORT_MONTH=%s\n' "${_runtime[export_month]}"
  printf 'MONTH_START=%s\n' "${_runtime[month_start]}"
  printf 'MONTH_END=%s\n\n' "${_runtime[month_end]}"
}
