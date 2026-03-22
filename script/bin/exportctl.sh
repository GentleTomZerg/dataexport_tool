#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/common/strict.sh"
source "$ROOT_DIR/lib/config/properties.sh"
source "$ROOT_DIR/lib/export/profile.sh"
source "$ROOT_DIR/lib/export/job.sh"
source "$ROOT_DIR/lib/export/plan.sh"
source "$ROOT_DIR/lib/sql/render.sh"
source "$ROOT_DIR/lib/exec/db.sh"
source "$ROOT_DIR/lib/artifact/pipeline.sh"

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
  local selectors_name="$2"
  local -n cli_ctx="$cli_name"
  local -A props=()
  local -A runtime=()
  local -a runnable_jobs=()
  local -a failed_jobs=()
  local total_jobs=0
  local ok_jobs=0
  local failed_count=0
  local job_name

  init_runtime_context "${cli_ctx[date]:-}" runtime
  load_all_properties "$cli_name" props
  resolve_job_selectors props "$selectors_name" runnable_jobs

  if [[ "${#runnable_jobs[@]}" -eq 0 ]]; then
    printf 'No runnable jobs resolved.\n' >&2
    print_summary "$total_jobs" "$ok_jobs" "$failed_count" failed_jobs
    return 0
  fi

  print_runtime_context runtime
  print_env_properties props

  for job_name in "${runnable_jobs[@]}"; do
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
  local -a selectors=()

  if ! parse_exportctl_args cli selectors "$@"; then
    usage >&2
    exit 1
  fi

  case "${cli[cmd]}" in
    validate|plan|run)
      run_export_command cli selectors
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

print_job_header() {
  local job_name="$1"

  printf '== Job: %s ==\n' "$job_name"
}

print_validate_ok() {
  printf 'STATUS=OK\n\n'
}

print_job_note() {
  local job_name="$1"
  local message="$2"

  printf '[%s] %s\n' "$job_name" "$message"
}

print_job_error() {
  local job_name="$1"
  local message="$2"

  printf '[%s] %s\n' "$job_name" "$message" >&2
}

file_line_count() {
  local path="$1"

  awk 'END { print NR + 0 }' "$path"
}

file_byte_size() {
  local path="$1"

  wc -c <"$path" | tr -d '[:space:]'
}

record_plan_failure() {
  local job_name="$1"
  printf 'STATUS=FAILED\n\n'
  print_job_error "$job_name" 'Plan build failed.'
}

execute_run_mode() {
  local plan_name="$1"
  local profile_name="$2"
  local job_name="$3"
  local -n job_plan="$plan_name"
  local export_lines export_bytes artifact_bytes

  print_plan "$plan_name"

  print_job_note "$job_name" "Starting export: db_type=${job_plan[db_type]} file=${job_plan[export_file]}"
  if ! execute_plan_export "$plan_name" "$profile_name"; then
    print_job_error "$job_name" 'Export failed.'
    return 1
  fi

  export_lines="$(file_line_count "${job_plan[export_file]}")"
  export_bytes="$(file_byte_size "${job_plan[export_file]}")"
  print_job_note "$job_name" "Export finished: file=${job_plan[export_file]} lines=${export_lines} bytes=${export_bytes}"

  if ! run_artifact_pipeline "$plan_name"; then
    print_job_error "$job_name" 'Artifact pipeline failed.'
    return 1
  fi

  if [[ -n "${job_plan[artifact_path]:-}" && -f "${job_plan[artifact_path]}" ]]; then
    artifact_bytes="$(file_byte_size "${job_plan[artifact_path]}")"
    print_job_note "$job_name" "Final artifact ready: file=${job_plan[artifact_path]} bytes=${artifact_bytes}"
  fi

  print_job_note "$job_name" 'Completed successfully.'
}

process_job() {
  local cli_name="$1"
  local props_name="$2"
  local job_name="$3"
  local -n cli_ctx="$cli_name"
  local -A profile=()
  local -A job=()
  local -A plan=()

  print_job_header "$job_name"

  if ! build_export_plan "$props_name" "$job_name" profile job plan; then
    record_plan_failure "$job_name"
    return 1
  fi

  plan[sql]="$(render_select_sql plan)"

  case "${cli_ctx[cmd]}" in
    validate)
      print_validate_ok
      print_job_note "$job_name" 'Validation succeeded.'
      ;;
    plan)
      print_plan plan
      print_job_note "$job_name" 'Plan generated.'
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
  local out_name="$2"
  local -n runtime_ctx="$out_name"
  local epoch month_start next_month_epoch next_month_first

  if [[ -z "$run_date" ]]; then
    run_date="$(date +%F)"
  fi

  runtime_ctx[export_date]="$run_date"
  runtime_ctx[today]="$run_date"

  if [[ "$(uname)" == "Darwin" ]]; then
    epoch="$(date -j -f "%Y-%m-%d" "$run_date" "+%s")"
    runtime_ctx[yesterday]="$(date -r $((epoch - 86400)) "+%F")"
    runtime_ctx[export_month]="$(date -r "$epoch" "+%Y-%m")"
    month_start="$(date -r "$epoch" "+%Y-%m-01")"
    runtime_ctx[month_start]="$month_start"
    next_month_epoch="$(date -j -f "%Y-%m-%d" "$month_start" "+%s")"
    next_month_epoch=$((next_month_epoch + 32 * 86400))
    next_month_first="$(date -r "$next_month_epoch" "+%Y-%m-01")"
    runtime_ctx[month_end]="$(date -r $(($(date -j -f "%Y-%m-%d" "$next_month_first" "+%s") - 86400)) "+%F")"
  else
    runtime_ctx[yesterday]="$(date -d "$run_date -1 day" +%F)"
    runtime_ctx[export_month]="$(date -d "$run_date" +%Y-%m)"
    runtime_ctx[month_start]="$(date -d "$run_date" +%Y-%m-01)"
    runtime_ctx[month_end]="$(date -d "${runtime_ctx[month_start]} +1 month -1 day" +%F)"
  fi

  export EXPORT_DATE="${runtime_ctx[export_date]}"
  export TODAY="${runtime_ctx[today]}"
  export YESTERDAY="${runtime_ctx[yesterday]}"
  export EXPORT_MONTH="${runtime_ctx[export_month]}"
  export MONTH_START="${runtime_ctx[month_start]}"
  export MONTH_END="${runtime_ctx[month_end]}"
}

print_runtime_context() {
  local runtime_name="$1"
  local -n runtime_ctx="$runtime_name"

  printf '== Runtime ==\n'
  printf 'EXPORT_DATE=%s\n' "${runtime_ctx[export_date]}"
  printf 'TODAY=%s\n' "${runtime_ctx[today]}"
  printf 'YESTERDAY=%s\n' "${runtime_ctx[yesterday]}"
  printf 'EXPORT_MONTH=%s\n' "${runtime_ctx[export_month]}"
  printf 'MONTH_START=%s\n' "${runtime_ctx[month_start]}"
  printf 'MONTH_END=%s\n\n' "${runtime_ctx[month_end]}"
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
  local -n cli_ctx="$cli_name"

  if [[ -n "${cli_ctx[env_config]:-}" ]]; then
    load_props_from_file "${cli_ctx[env_config]}" "$props_name"
    export_env_properties "$props_name"
  fi
  load_props_from_file "${cli_ctx[db_config]}" "$props_name"
  load_props_from_file "${cli_ctx[jobs_config]}" "$props_name"
}

resolve_job_selectors() {
  local props_name="$1"
  local selectors_name="$2"
  local out_name="$3"
  local -n requested_selectors="$selectors_name"
  local -n resolved_jobs="$out_name"
  local selector job_name
  local -a all_jobs=()
  local -A selected=()
  local -A known=()

  mapfile -t all_jobs < <(list_export_jobs "$props_name")
  for job_name in "${all_jobs[@]}"; do
    known["$job_name"]=1
  done

  if [[ "${#requested_selectors[@]}" -eq 0 ]]; then
    resolved_jobs=("${all_jobs[@]}")
    return 0
  fi

  for selector in "${requested_selectors[@]}"; do
    if [[ -n "${known[$selector]:-}" ]]; then
      selected["$selector"]=1
    else
      printf 'ERROR: unknown selector %s\n' "$selector" >&2
    fi
  done

  resolved_jobs=()
  for job_name in "${!selected[@]}"; do
    resolved_jobs+=("$job_name")
  done
  if [[ "${#resolved_jobs[@]}" -gt 0 ]]; then
    mapfile -t resolved_jobs < <(printf '%s\n' "${resolved_jobs[@]}" | sort)
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
  local selectors_name="$2"
  local -n cli_ctx="$cli_name"
  local -n requested_selectors="$selectors_name"

  cli_ctx[cmd]=""
  cli_ctx[db_config]=""
  cli_ctx[jobs_config]=""
  cli_ctx[env_config]=""
  cli_ctx[date]=""
  requested_selectors=()
}

parse_export_args() {
  local cli_name="$1"
  local selectors_name="$2"
  shift 2
  local -n cli_ctx="$cli_name"
  local -n requested_selectors="$selectors_name"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --db-config)
        args_require_value "$@" || return 1
        cli_ctx[db_config]="$2"
        shift 2
        ;;
      --jobs-config)
        args_require_value "$@" || return 1
        cli_ctx[jobs_config]="$2"
        shift 2
        ;;
      --env-config)
        args_require_value "$@" || return 1
        cli_ctx[env_config]="$2"
        shift 2
        ;;
      --date)
        args_require_value "$@" || return 1
        cli_ctx[date]="$2"
        shift 2
        ;;
      -h|--help)
        return 1
        ;;
      *)
        requested_selectors+=("$1")
        shift
        ;;
    esac
  done

  [[ -n "${cli_ctx[db_config]}" && -n "${cli_ctx[jobs_config]}" ]] || return 1
  args_validate_date "${cli_ctx[date]}" || return 1
}

parse_exportctl_args() {
  local cli_name="$1"
  local selectors_name="$2"
  shift 2
  local -n cli_ctx="$cli_name"

  init_cli_context "$cli_name" "$selectors_name"

  cli_ctx[cmd]="${1:-}"
  [[ -n "${cli_ctx[cmd]}" ]] || return 1
  shift

  case "${cli_ctx[cmd]}" in
    validate|plan|run)
      parse_export_args "$cli_name" "$selectors_name" "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

main "$@"
