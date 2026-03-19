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
source "$ROOT_DIR/lib/sql_builder.sh"
source "$ROOT_DIR/lib/sql_exec.sh"

usage() {
  cat <<'EOF'
Usage:
  export_data.sh --db-config file --jobs-config file [--job name|--jobs a,b] [--date YYYY-MM-DD] [--execute]

Environment:
  (none)

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
  ACTIVE_DB_PROFILE=""
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
  # Uses GNU date for relative date math (e.g., "-1 day").
  export EXPORT_DATE="$run_date"
  export TODAY="$EXPORT_DATE"
  export YESTERDAY="$(date -d "$EXPORT_DATE -1 day" +%F)"
  export EXPORT_MONTH="$(date -d "$EXPORT_DATE" +%Y-%m)"
  export MONTH_START="$(date -d "$EXPORT_DATE" +%Y-%m-01)"
  export MONTH_END="$(date -d "$MONTH_START +1 month -1 day" +%F)"
}

load_db_properties() {
  # Uses lib/db_config.sh which sources properties internally.
  load_properties "$DB_CONFIG"
}

load_job_config_file() {
  # Uses lib/job_config.sh which sources properties internally.
  load_properties "$JOBS_CONFIG"
}

validate_job_bundle() {
  local job="$1"
  # Keep validation orchestration here for a single, clear entry point.
  # Primitive validators live in the lib files for reuse.
  load_job_config "$job"
  validate_job_config "$job"
  load_job_filters "$job"
  validate_job_filters "$job"
  load_job_splits "$job"
  validate_job_splits "$job"
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

run_jobs() {
  local job
  for job in "${JOBS_LIST[@]}"; do
    job="${job##+([[:space:]])}"
    job="${job%%+([[:space:]])}"
    [[ -z "$job" ]] && continue

    # Load and validate per-job config, filters, and split rules.
    validate_job_bundle "$job"

    if [[ -z "$JOB_DB_PROFILE" ]]; then
      echo "Missing DB profile for job: $job (set job.${job}.DB_PROFILE)" >&2
      return 1
    fi

    if [[ "$JOB_DB_PROFILE" != "$ACTIVE_DB_PROFILE" || -z "${DB_HOST:-}" ]]; then
      ACTIVE_DB_PROFILE="$JOB_DB_PROFILE"
      load_db_profile "$ACTIVE_DB_PROFILE"
    fi

    local SQL
    SQL="$(build_select_sql)"

    echo "== Job: $job =="
    echo "DB_PROFILE=$ACTIVE_DB_PROFILE"
    echo "DB_HOST=$DB_HOST"
    echo "DB_PORT=$DB_PORT"
    echo "DB_NAME=$DB_NAME"
    echo "DB_USER=$DB_USER"
    echo "DB_TYPE=$DB_TYPE"
    echo "DB_CONFIG=$DB_CONFIG"
    echo "JOBS_CONFIG=$JOBS_CONFIG"
    echo "TABLE=$JOB_TABLE"
    echo "SQL=$SQL"
    echo "EXPORT_FILE=${JOB_EXPORT_FILE:-}"
    echo "FIELD_SEPARATOR=$JOB_FIELD_SEPARATOR"
    echo "LINE_TERMINATOR=$JOB_LINE_TERMINATOR"
    echo "EXPORT_DATE=$EXPORT_DATE"
    echo "YESTERDAY=$YESTERDAY"
    echo "EXPORT_MONTH=$EXPORT_MONTH"
    echo "MONTH_START=$MONTH_START"
    echo "MONTH_END=$MONTH_END"
    echo

    if [[ "$EXECUTE" -eq 1 ]]; then
      if [[ -z "${JOB_EXPORT_FILE:-}" ]]; then
        echo "Missing EXPORT_FILE for job: $job" >&2
        return 1
      fi
      mkdir -p "$(dirname "$JOB_EXPORT_FILE")"
      sql_exec_export "$SQL" "$JOB_EXPORT_FILE" "$JOB_FIELD_SEPARATOR" "$JOB_LINE_TERMINATOR"
    fi
  done
}

main() {
  parse_args "$@"
  if [[ "$SHOW_HELP" -eq 1 ]]; then
    return 0
  fi
  require_args
  init_runtime_dates "$RUN_DATE"
  load_db_properties
  load_job_config_file
  resolve_jobs
  run_jobs
}

main "$@"
