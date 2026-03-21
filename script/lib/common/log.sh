#!/usr/bin/env bash

log_info() {
  printf 'INFO: %s\n' "$*" >&2
}

log_warn() {
  printf 'WARN: %s\n' "$*" >&2
}

log_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

log_job_error() {
  local job_name="$1"
  shift
  printf 'JOB_FAIL name=%s %s\n' "$job_name" "$*" >&2
}

log_job_ok() {
  local job_name="$1"
  shift
  printf 'JOB_OK name=%s %s\n' "$job_name" "$*" >&2
}
