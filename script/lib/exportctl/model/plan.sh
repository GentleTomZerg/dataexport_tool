#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/profile.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/job.sh"

build_export_plan() {
  local props_name="$1"
  local job_name="$2"
  local profile_name="$3"
  local job_out_name="$4"
  local plan_name="$5"
  local -n _profile="$profile_name"
  local -n _job="$job_out_name"
  local -n _plan="$plan_name"

  load_export_job "$props_name" "$job_name" "$job_out_name" || return 1
  load_export_profile "$props_name" "${_job[db_profile]}" "$profile_name" || return 1

  _plan[job_name]="${_job[name]}"
  _plan[db_profile]="${_job[db_profile]}"
  _plan[db_type]="${_profile[type]}"
  _plan[db_host]="${_profile[host]}"
  _plan[db_port]="${_profile[port]}"
  _plan[db_name]="${_profile[name]}"
  _plan[db_user]="${_profile[user]}"
  _plan[password_file]="${_profile[password_file]}"
  _plan[password_key_file]="${_profile[password_key_file]}"
  _plan[table]="${_job[table]}"
  _plan[columns]="${_job[columns]}"
  _plan[where_raw]="${_job[where]}"
  _plan[splits]="${_job[splits]}"
  _plan[export_file]="${_job[export_file]}"
  _plan[field_separator]="${_job[field_separator]}"
  _plan[line_terminator]="${_job[line_terminator]}"
  _plan[compress_enabled]="${_job[compress_enabled],,}"
  _plan[compress_mode]="${_job[compress_mode],,}"
  _plan[compress_overwrite]="${_job[compress_overwrite],,}"
  _plan[compress_remove_original]="${_job[compress_remove_original],,}"
  _plan[transfer_enabled]="${_job[transfer_enabled],,}"
  _plan[transfer_dir]="${_job[transfer_dir]}"
  _plan[transfer_mode]="${_job[transfer_mode],,}"
  _plan[transfer_overwrite]="${_job[transfer_overwrite],,}"
  _plan[transfer_rename]="${_job[transfer_rename]}"

  if [[ -z "${_plan[export_file]}" ]]; then
    printf 'ERROR: job %s missing EXPORT_FILE\n' "$job_name" >&2
    return 1
  fi
}
