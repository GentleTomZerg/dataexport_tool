#!/usr/bin/env bash

summary_init() {
  local out_name="$1"
  local -n _out="$out_name"
  _out[total]=0
  _out[ok]=0
  _out[failed]=0
  _out[failed_jobs]=""
}

summary_mark_ok() {
  local out_name="$1"
  local job_name="$2"
  local -n _out="$out_name"
  _out[total]=$((_out[total] + 1))
  _out[ok]=$((_out[ok] + 1))
  log_job_ok "$job_name" "stage=complete"
}

summary_mark_failed() {
  local out_name="$1"
  local job_name="$2"
  local -n _out="$out_name"
  _out[total]=$((_out[total] + 1))
  _out[failed]=$((_out[failed] + 1))
  if [[ -n "${_out[failed_jobs]}" ]]; then
    _out[failed_jobs]+=" "
  fi
  _out[failed_jobs]+="$job_name"
}

summary_print() {
  local out_name="$1"
  local -n _out="$out_name"
  printf 'SUMMARY total=%s ok=%s failed=%s\n' "${_out[total]}" "${_out[ok]}" "${_out[failed]}"
  if [[ -n "${_out[failed_jobs]}" ]]; then
    printf 'FAILED_JOBS=%s\n' "${_out[failed_jobs]}"
  fi
}
