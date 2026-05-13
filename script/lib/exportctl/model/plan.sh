#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/job.sh"

build_export_plan() {
  local props_name="$1"
  local job_name="$2"
  local plan_name="$3"
  local -A job=()
  local -n _plan="$plan_name"

  load_export_job "$props_name" "$job_name" "job" || return 1

  _plan[job_name]="${job[name]}"
  _plan[db_type]="${job[db_type]}"
  _plan[db_host]="${job[db_host]}"
  _plan[db_port]="${job[db_port]}"
  _plan[db_name]="${job[db_name]}"
  _plan[db_user]="${job[db_user]}"
  _plan[password_file]="${job[password_file]}"
  _plan[password_key_file]="${job[password_key_file]}"
  _plan[table]="${job[table]}"
  _plan[columns]="${job[columns]}"
  _plan[where_raw]="${job[where]}"
  _plan[splits]="${job[splits]}"
  _plan[export_file]="${job[export_file]}"
  _plan[field_separator]="${job[field_separator]}"
  _plan[line_terminator]="${job[line_terminator]}"
  _plan[field_separator_data_replacement]="${job[field_separator_data_replacement]}"
  _plan[compress_enabled]="${job[compress_enabled],,}"
  _plan[compress_mode]="${job[compress_mode],,}"
  _plan[compress_overwrite]="${job[compress_overwrite],,}"
  _plan[compress_remove_original]="${job[compress_remove_original],,}"
  _plan[transfer_enabled]="${job[transfer_enabled],,}"
  _plan[transfer_dir]="${job[transfer_dir]}"
  _plan[transfer_mode]="${job[transfer_mode],,}"
  _plan[transfer_overwrite]="${job[transfer_overwrite],,}"
  _plan[transfer_rename]="${job[transfer_rename]}"

  if [[ -z "${_plan[export_file]}" ]]; then
    printf 'ERROR: job %s missing EXPORT_FILE\n' "$job_name" >&2
    return 1
  fi
}
