#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/common/strict.sh"
source "$ROOT_DIR/lib/config/properties.sh"
source "$ROOT_DIR/lib/exportctl/model/profile.sh"
source "$ROOT_DIR/lib/exportctl/model/job.sh"
source "$ROOT_DIR/lib/exportctl/model/plan.sh"
source "$ROOT_DIR/lib/exportctl/sql.sh"
source "$ROOT_DIR/lib/exportctl/run/db.sh"
source "$ROOT_DIR/lib/exportctl/run/artifact.sh"

setup_shell

###############################################################################
# CLI Usage
###############################################################################

usage() {
  cat <<'EOF'
Usage:
  exportctl.sh validate --db-config FILE --jobs-config FILE [--env-config FILE] [job selectors...]
  exportctl.sh plan --db-config FILE --jobs-config FILE [--env-config FILE] [--date YYYY-MM-DD] [job selectors...]
  exportctl.sh run --db-config FILE --jobs-config FILE [--env-config FILE] [--date YYYY-MM-DD] [job selectors...]

Selectors:
  users orders

Exit codes:
  1 only for invalid CLI arguments.
  0 for all runtime outcomes; failures are logged and summarized.
EOF
}

###############################################################################
# Command Flow
###############################################################################

run_export_command() {
  local cli_name="$1"
  local requested_jobs_name="$2"
  local -n cli_ref="$cli_name"
  local -A props=()
  local -A runtime=()
  local -a resolved_jobs=()
  local -a failed_jobs=()
  local total_jobs=0
  local ok_jobs=0
  local failed_count=0
  local job_name

  init_runtime_context "${cli_ref[date]:-}" runtime
  load_all_properties "$cli_name" props
  resolve_requested_jobs props "$requested_jobs_name" resolved_jobs

  if [[ "${#resolved_jobs[@]}" -eq 0 ]]; then
    printf 'No runnable jobs resolved.\n' >&2
    print_summary "$total_jobs" "$ok_jobs" "$failed_count" failed_jobs
    return 0
  fi

  print_runtime_context runtime
  print_env_properties props

  for job_name in "${resolved_jobs[@]}"; do
    total_jobs=$((total_jobs + 1))
    if process_job "$cli_name" props "$job_name"; then
      ok_jobs=$((ok_jobs + 1))
    else
      failed_count=$((failed_count + 1))
      failed_jobs+=("$job_name")
    fi
  done

  print_summary "$total_jobs" "$ok_jobs" "$failed_count" failed_jobs
  return 0
}

main() {
  local -A cli=()
  local -a requested_jobs=()

  if ! parse_exportctl_args cli requested_jobs "$@"; then
    usage >&2
    exit 1
  fi

  case "${cli[cmd]}" in
  validate | plan | run)
    run_export_command cli requested_jobs
    ;;
  *)
    usage >&2
    exit 1
    ;;
  esac
}

###############################################################################
# Per-Job Flow
###############################################################################

print_plan() {
  local plan_name="$1"
  local -n job_plan="$plan_name"

  printf 'DB_PROFILE=%s\n' "${job_plan[db_profile]}"
  printf 'DB_TYPE=%s\n' "${job_plan[db_type]}"
  printf 'DB_HOST=%s\n' "${job_plan[db_host]}"
  printf 'DB_PORT=%s\n' "${job_plan[db_port]}"
  printf 'TABLE=%s\n' "${job_plan[table]}"
  printf 'COLUMNS=%s\n' "${job_plan[columns]}"
  printf 'EXPORT_FILE=%s\n' "${job_plan[export_file]}"
  printf 'FIELD_SEPARATOR=%s\n' "${job_plan[field_separator]}"
  printf 'LINE_TERMINATOR=%s\n' "${job_plan[line_terminator]}"
  printf 'SQL=%s\n' "${job_plan[sql]}"
  printf '\n'
}

file_line_count() {
  local path="$1"

  awk 'END { print NR + 0 }' "$path"
}

file_byte_size() {
  local path="$1"

  wc -c <"$path" | tr -d '[:space:]'
}

execute_run_mode() {
  local plan_name="$1"
  local profile_name="$2"
  local job_name="$3"
  local -n job_plan="$plan_name"
  local export_lines export_bytes artifact_bytes

  print_plan "$plan_name"

  printf '[%s] Starting export: db_type=%s file=%s\n' "$job_name" "${job_plan[db_type]}" "${job_plan[export_file]}"
  if ! execute_plan_export "$plan_name" "$profile_name"; then
    printf '[%s] Export failed.\n' "$job_name" >&2
    return 1
  fi

  export_lines="$(file_line_count "${job_plan[export_file]}")"
  export_bytes="$(file_byte_size "${job_plan[export_file]}")"
  printf '[%s] Export finished: file=%s lines=%s bytes=%s\n' "$job_name" "${job_plan[export_file]}" "$export_lines" "$export_bytes"

  if ! run_artifact_pipeline "$plan_name"; then
    printf '[%s] Artifact pipeline failed.\n' "$job_name" >&2
    return 1
  fi

  if [[ -n "${job_plan[artifact_path]:-}" && -f "${job_plan[artifact_path]}" ]]; then
    artifact_bytes="$(file_byte_size "${job_plan[artifact_path]}")"
    printf '[%s] Final artifact ready: file=%s bytes=%s\n' "$job_name" "${job_plan[artifact_path]}" "$artifact_bytes"
  fi

  printf '[%s] Completed successfully.\n' "$job_name"
}

process_job() {
  local cli_name="$1"
  local props_name="$2"
  local job_name="$3"
  local -n cli_ref="$cli_name"
  local -A profile=()
  local -A job=()
  local -A plan=()

  printf '== Job: %s ==\n' "$job_name"

  if ! build_export_plan "$props_name" "$job_name" profile job plan; then
    printf '[%s] Plan build failed.\n' "$job_name" >&2
    return 1
  fi

  plan[sql]="$(render_select_sql plan)"

  case "${cli_ref[cmd]}" in
  validate)
    printf '[%s] Validation succeeded.\n' "$job_name"
    ;;
  plan)
    print_plan plan
    printf '[%s] Plan generated.\n' "$job_name"
    ;;
  run)
    execute_run_mode plan profile "$job_name"
    return $?
    ;;
  esac

  return 0
}

###############################################################################
# Batch Summary
###############################################################################

print_summary() {
  local total_jobs="$1"
  local ok_jobs="$2"
  local failed_count="$3"
  local failed_jobs_name="$4"
  local -n failed_jobs_ref="$failed_jobs_name"

  printf 'Summary: total=%s ok=%s failed=%s\n' "$total_jobs" "$ok_jobs" "$failed_count"
  if [[ "${#failed_jobs_ref[@]}" -gt 0 ]]; then
    printf 'Failed jobs: %s\n' "${failed_jobs_ref[*]}"
  fi
}

###############################################################################
# Runtime And Environment
###############################################################################

init_runtime_context() {
  local run_date="$1"
  local runtime_name="$2"
  local -n runtime_ref="$runtime_name"
  local epoch month_start next_month_epoch next_month_first

  if [[ -z "$run_date" ]]; then
    run_date="$(date +%F)"
  fi

  runtime_ref[export_date]="$run_date"
  runtime_ref[today]="$run_date"
  runtime_ref[bjs_date]="${run_date//-/}"

  if [[ "$(uname)" == "Darwin" ]]; then
    epoch="$(date -j -f "%Y-%m-%d" "$run_date" "+%s")"
    runtime_ref[yesterday]="$(date -r $((epoch - 86400)) "+%F")"
    runtime_ref[export_month]="$(date -r "$epoch" "+%Y-%m")"
    month_start="$(date -r "$epoch" "+%Y-%m-01")"
    runtime_ref[month_start]="$month_start"
    next_month_epoch="$(date -j -f "%Y-%m-%d" "$month_start" "+%s")"
    next_month_epoch=$((next_month_epoch + 32 * 86400))
    next_month_first="$(date -r "$next_month_epoch" "+%Y-%m-01")"
    runtime_ref[month_end]="$(date -r $(($(date -j -f "%Y-%m-%d" "$next_month_first" "+%s") - 86400)) "+%F")"
  else
    runtime_ref[yesterday]="$(date -d "$run_date -1 day" +%F)"
    runtime_ref[export_month]="$(date -d "$run_date" +%Y-%m)"
    runtime_ref[month_start]="$(date -d "$run_date" +%Y-%m-01)"
    runtime_ref[month_end]="$(date -d "${runtime_ref[month_start]} +1 month -1 day" +%F)"
  fi

  export EXPORT_DATE="${runtime_ref[export_date]}"
  export TODAY="${runtime_ref[today]}"
  export YESTERDAY="${runtime_ref[yesterday]}"
  export EXPORT_MONTH="${runtime_ref[export_month]}"
  export MONTH_START="${runtime_ref[month_start]}"
  export MONTH_END="${runtime_ref[month_end]}"
  export BJS_DATE="${runtime_ref[bjs_date]}"
}

print_runtime_context() {
  local runtime_name="$1"
  local -n runtime_ref="$runtime_name"

  printf '== Runtime ==\n'
  printf 'EXPORT_DATE=%s\n' "${runtime_ref[export_date]}"
  printf 'TODAY=%s\n' "${runtime_ref[today]}"
  printf 'YESTERDAY=%s\n' "${runtime_ref[yesterday]}"
  printf 'EXPORT_MONTH=%s\n' "${runtime_ref[export_month]}"
  printf 'MONTH_START=%s\n' "${runtime_ref[month_start]}"
  printf 'MONTH_END=%s\n' "${runtime_ref[month_end]}"
  printf 'BJS_DATE=%s\n\n' "${runtime_ref[bjs_date]}"
}

export_env_properties() {
  local props_name="$1"
  local key value

  while IFS= read -r key; do
    [[ "$key" == ENV_* ]] || continue
    value="$(props_get "$props_name" "$key")"
    printf -v "$key" '%s' "$value"
    export "$key"
  done < <(props_keys "$props_name" "ENV_")
}

print_env_properties() {
  local props_name="$1"
  local key
  local -a env_keys=()

  mapfile -t env_keys < <(props_keys "$props_name" "ENV_")
  if [[ "${#env_keys[@]}" -eq 0 ]]; then
    return 0
  fi

  printf '== Environment ==\n'
  for key in "${env_keys[@]}"; do
    [[ "$key" == ENV_* ]] || continue
    printf '%s=%s\n' "$key" "${!key:-}"
  done
  printf '\n'
}

load_all_properties() {
  local cli_name="$1"
  local props_name="$2"
  local -n cli_ref="$cli_name"

  if [[ -n "${cli_ref[env_config]:-}" ]]; then
    load_props_from_file "${cli_ref[env_config]}" "$props_name"
    export_env_properties "$props_name"
  fi
  load_props_from_file "${cli_ref[db_config]}" "$props_name"
  load_props_from_file "${cli_ref[jobs_config]}" "$props_name"
}

resolve_requested_jobs() {
  local props_name="$1"
  local requested_jobs_name="$2"
  local resolved_jobs_name="$3"
  local -n requested_jobs_ref="$requested_jobs_name"
  local -n resolved_jobs_ref="$resolved_jobs_name"
  local requested_job job_name
  local -a configured_jobs=()
  local -A requested_lookup=()
  local -A configured_lookup=()

  mapfile -t configured_jobs < <(list_export_jobs "$props_name")
  for job_name in "${configured_jobs[@]}"; do
    configured_lookup["$job_name"]=1
  done

  if [[ "${#requested_jobs_ref[@]}" -eq 0 ]]; then
    resolved_jobs_ref=("${configured_jobs[@]}")
    return 0
  fi

  for requested_job in "${requested_jobs_ref[@]}"; do
    if [[ -n "${configured_lookup[$requested_job]:-}" ]]; then
      requested_lookup["$requested_job"]=1
    else
      printf 'ERROR: unknown job %s\n' "$requested_job" >&2
    fi
  done

  resolved_jobs_ref=()
  for job_name in "${!requested_lookup[@]}"; do
    resolved_jobs_ref+=("$job_name")
  done
  if [[ "${#resolved_jobs_ref[@]}" -gt 0 ]]; then
    mapfile -t resolved_jobs_ref < <(printf '%s\n' "${resolved_jobs_ref[@]}" | sort)
  fi
}

###############################################################################
# Argument Parsing
###############################################################################

args_require_value() {
  [[ $# -ge 2 && -n "${2:-}" && "${2:0:1}" != "-" ]]
}

args_validate_date() {
  [[ -z "$1" || "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

init_cli_context() {
  local cli_name="$1"
  local requested_jobs_name="$2"
  local -n cli_ref="$cli_name"
  local -n requested_jobs_ref="$requested_jobs_name"

  cli_ref[cmd]=""
  cli_ref[db_config]=""
  cli_ref[jobs_config]=""
  cli_ref[env_config]=""
  cli_ref[date]=""
  requested_jobs_ref=()
}

parse_export_args() {
  local cli_name="$1"
  local requested_jobs_name="$2"
  shift 2
  local -n cli_ref="$cli_name"
  local -n requested_jobs_ref="$requested_jobs_name"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --db-config)
      args_require_value "$@" || return 1
      cli_ref[db_config]="$2"
      shift 2
      ;;
    --jobs-config)
      args_require_value "$@" || return 1
      cli_ref[jobs_config]="$2"
      shift 2
      ;;
    --env-config)
      args_require_value "$@" || return 1
      cli_ref[env_config]="$2"
      shift 2
      ;;
    --date)
      args_require_value "$@" || return 1
      cli_ref[date]="$2"
      shift 2
      ;;
    -h | --help)
      return 1
      ;;
    *)
      requested_jobs_ref+=("$1")
      shift
      ;;
    esac
  done

  [[ -n "${cli_ref[db_config]}" && -n "${cli_ref[jobs_config]}" ]] || return 1
  args_validate_date "${cli_ref[date]}" || return 1
}

parse_exportctl_args() {
  local cli_name="$1"
  local requested_jobs_name="$2"
  shift 2
  local -n cli_ref="$cli_name"

  init_cli_context "$cli_name" "$requested_jobs_name"

  cli_ref[cmd]="${1:-}"
  [[ -n "${cli_ref[cmd]}" ]] || return 1
  shift

  case "${cli_ref[cmd]}" in
  validate | plan | run)
    parse_export_args "$cli_name" "$requested_jobs_name" "$@"
    ;;
  *)
    return 1
    ;;
  esac
}

main "$@"
