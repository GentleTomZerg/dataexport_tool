#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This script requires bash. Run: bash export_data.sh ..." >&2
  exit 1
fi
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/db_config.sh"
source "$ROOT_DIR/lib/crypto.sh"
source "$ROOT_DIR/lib/job_config.sh"
source "$ROOT_DIR/lib/post_export.sh"
source "$ROOT_DIR/lib/sql_builder.sh"
source "$ROOT_DIR/lib/sql_exec.sh"

usage() {
  cat <<'EOF'
Usage:
  export_data.sh --db-config file --jobs-config file [--env-config file] [--job name|--jobs a,b] [--date YYYY-MM-DD] [--execute]

Environment:
  ENV_* values can be loaded from --env-config and are exported for config expansion.

Notes:
  - Requires bash and GNU date (uses `date -d` for relative date math).
  - --db-config and --jobs-config are required.
  - Each job must define job.<name>.DB_PROFILE.
  - Default behavior prints SQL only. Use --execute to run exports.
EOF
}

parse_args() {
  DB_CONFIG=""
  JOBS_CONFIG=""
  ENV_CONFIG=""
  JOBS_ARG=""
  RUN_DATE=""
  SHOW_HELP=0
  EXECUTE=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --db-config)
      DB_CONFIG="$2"
      shift 2
      ;;
    --jobs-config)
      JOBS_CONFIG="$2"
      shift 2
      ;;
    --env-config)
      ENV_CONFIG="$2"
      shift 2
      ;;
    --job)
      JOBS_ARG="$2"
      shift 2
      ;;
    --jobs)
      JOBS_ARG="$2"
      shift 2
      ;;
    --date)
      RUN_DATE="$2"
      shift 2
      ;;
    --execute)
      EXECUTE=1
      shift 1
      ;;
    -h | --help)
      usage
      SHOW_HELP=1
      return 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      return 1
      ;;
    esac
  done
}

require_args() {
  local missing=()
  [[ -z "$DB_CONFIG" ]] && missing+=("--db-config")
  [[ -z "$JOBS_CONFIG" ]] && missing+=("--jobs-config")
  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "Missing required args: ${missing[*]}" >&2
    usage >&2
    return 1
  fi
}

init_runtime_dates() {
  local run_date="$1"
  if [[ -z "$run_date" ]]; then
    run_date="$(date +%F)"
  fi
  export EXPORT_DATE="$run_date"
  export TODAY="$EXPORT_DATE"

  if [[ "$(uname)" == "Darwin" ]]; then
    local epoch
    epoch="$(date -j -f "%Y-%m-%d" "$EXPORT_DATE" "+%s")"
    export YESTERDAY="$(date -r $((epoch - 86400)) "+%F")"
    export EXPORT_MONTH="$(date -r "$epoch" "+%Y-%m")"
    export MONTH_START="$(date -r "$epoch" "+%Y-%m-01")"
    local next_month_epoch
    next_month_epoch="$(date -j -f "%Y-%m-%d" "$MONTH_START" "+%s")"
    next_month_epoch=$((next_month_epoch + 32 * 86400))
    local next_month_first
    next_month_first="$(date -r "$next_month_epoch" "+%Y-%m-01")"
    export MONTH_END="$(date -r $(($(date -j -f "%Y-%m-%d" "$next_month_first" "+%s") - 86400)) "+%F")"
  else
    export YESTERDAY="$(date -d "$EXPORT_DATE -1 day" +%F)"
    export EXPORT_MONTH="$(date -d "$EXPORT_DATE" +%Y-%m)"
    export MONTH_START="$(date -d "$EXPORT_DATE" +%Y-%m-01)"
    export MONTH_END="$(date -d "$MONTH_START +1 month -1 day" +%F)"
  fi
}

print_runtime_dates() {
  echo "== Runtime Dates =="
  echo "EXPORT_DATE=$EXPORT_DATE"
  echo "TODAY=$TODAY"
  echo "YESTERDAY=$YESTERDAY"
  echo "EXPORT_MONTH=$EXPORT_MONTH"
  echo "MONTH_START=$MONTH_START"
  echo "MONTH_END=$MONTH_END"
  echo
}

export_env_vars() {
  local key
  if [[ -z "$ENV_CONFIG" ]]; then
    return 0
  fi
  while IFS= read -r key; do
    [[ "$key" == ENV_* ]] || continue
    export "$key=$(get_prop "$key")"
  done < <(list_props_by_prefix "ENV_")
}

print_env_properties() {
  local key
  if [[ -z "$ENV_CONFIG" ]]; then
    return 0
  fi

  echo "== Environment (ENV_*) =="
  while IFS= read -r key; do
    [[ "$key" == ENV_* ]] || continue
    echo "${key}=${!key}"
  done < <(list_props_by_prefix "ENV_")
  echo
}

resolve_jobs() {
  if [[ -n "$JOBS_ARG" ]]; then
    IFS=',' read -r -a JOBS_LIST <<<"$JOBS_ARG"
  else
    mapfile -t JOBS_LIST < <(list_jobs)
  fi

  if [[ "${#JOBS_LIST[@]}" -eq 0 ]]; then
    echo "No jobs specified. Use --job/--jobs or define job.<name>.* in export_jobs.properties." >&2
    return 1
  fi
}

## Load and validate everything for a single job.
load_and_validate_job() {
  local job="$1"
  load_job_config "$job"
  validate_db_profile_exists "$job"
  load_job_splits "$job"
  load_job_transfer "$job"
  load_job_compress "$job"
}

## Print job info and SQL to stdout.
print_job_info() {
  local job="$1"
  local sql="$2"

  echo "== Job: $job =="
  echo "DB_PROFILE=${DB[profile]}"
  echo "DB_TYPE=${DB[type]}"
  echo "DB_HOST=${DB[host]}"
  echo "DB_PORT=${DB[port]}"
  echo "TABLE=${JOB[table]}"
  echo "COLUMNS=${JOB[columns]}"
  echo "EXPORT_FILE=${JOB[export_file]:-}"
  echo "FIELD_SEPARATOR=${JOB[field_separator]}"
  echo "LINE_TERMINATOR=${JOB[line_terminator]}"
  echo "SQL=$sql"
  echo
}

## Execute export, compress, and transfer for a single job.
execute_export_for_job() {
  local job="$1"
  local sql="$2"

  if [[ -z "${JOB[export_file]:-}" ]]; then
    echo "Missing EXPORT_FILE for job: $job" >&2
    return 1
  fi
  if ! mkdir -p "$(dirname "${JOB[export_file]}")"; then
    echo "Failed to create export dir for job: $job" >&2
    return 1
  fi
  if ! sql_exec_export "$sql" "${JOB[export_file]}" "${JOB[field_separator]}" "${JOB[line_terminator]}"; then
    echo "sql_exec_export failed for job: $job" >&2
    return 1
  fi
  local line_count
  line_count="$(wc -l <"${JOB[export_file]}" | tr -d ' ')"
  echo "EXPORT_OK: ${JOB[export_file]} (lines=$line_count)"

  local artifact_path="${JOB[export_file]}"
  if [[ "${JOB_COMPRESS[enabled]}" == "true" ]]; then
    local before="$artifact_path"
    if ! artifact_path="$(compress_file "$artifact_path" "${JOB_COMPRESS[mode]}" "${JOB_COMPRESS[overwrite]}" "${JOB_COMPRESS[remove_original]}")"; then
      echo "Compress failed for job: $job" >&2
      return 1
    fi
    echo "COMPRESS_OK: $before -> $artifact_path (mode=${JOB_COMPRESS[mode]} remove_original=${JOB_COMPRESS[remove_original]})"
  fi
  if [[ "${JOB_TRANSFER[enabled]}" == "true" ]]; then
    local before="$artifact_path"
    if ! artifact_path="$(transfer_file "$artifact_path" "${JOB_TRANSFER[dir]}" "${JOB_TRANSFER[mode]}" "${JOB_TRANSFER[overwrite]}" "${JOB_TRANSFER[rename]}")"; then
      echo "Transfer failed for job: $job" >&2
      return 1
    fi
    echo "TRANSFER_OK: $before -> $artifact_path (mode=${JOB_TRANSFER[mode]} overwrite=${JOB_TRANSFER[overwrite]} rename=${JOB_TRANSFER[rename]:-})"
  fi
}

## Process a single job: validate, load DB, build SQL, optionally execute.
run_one_job() {
  local job="$1"
  local active_db_profile=""

  load_and_validate_job "$job"

  if [[ "${JOB[db_profile]}" != "$active_db_profile" || -z "${DB[host]:-}" ]]; then
    active_db_profile="${JOB[db_profile]}"
    if ! load_db_profile "$active_db_profile"; then
      echo "JOB_FAILED: $job (invalid DB profile: $active_db_profile)" >&2
      return 1
    fi
  fi

  local sql
  sql="$(build_select_sql)"

  print_job_info "$job" "$sql"

  if [[ "$EXECUTE" -eq 1 ]]; then
    execute_export_for_job "$job" "$sql"
  fi
}

run_jobs() {
  local job
  local failed_jobs=()
  for job in "${JOBS_LIST[@]}"; do
    job="${job##+([[:space:]])}"
    job="${job%%+([[:space:]])}"
    [[ -z "$job" ]] && continue

    if ! run_one_job "$job"; then
      failed_jobs+=("$job")
    fi
  done

  if [[ "${#failed_jobs[@]}" -gt 0 ]]; then
    echo "FAILED_JOBS=${failed_jobs[*]}" >&2
    return 0
  fi
}

main() {
  parse_args "$@"
  if [[ "$SHOW_HELP" -eq 1 ]]; then
    return 0
  fi
  require_args
  init_runtime_dates "$RUN_DATE"
  print_runtime_dates
  [[ -n "$ENV_CONFIG" ]] && load_properties "$ENV_CONFIG"
  export_env_vars
  print_env_properties
  load_properties "$DB_CONFIG"
  load_properties "$JOBS_CONFIG"
  resolve_jobs
  run_jobs
}

main "$@"
