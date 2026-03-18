#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This script requires bash. Run: bash export_data.sh ..." >&2
  exit 1
fi
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$ROOT_DIR/lib/db_config.sh"
source "$ROOT_DIR/lib/crypto.sh"
source "$ROOT_DIR/lib/job_config.sh"
source "$ROOT_DIR/lib/sql_builder.sh"
source "$ROOT_DIR/lib/sql_exec.sh"

usage() {
  cat <<'EOF'
Usage:
  ./export_data.sh [--db-props file] [--db-profile name] [--data-props file] [--job name|--jobs a,b] [--date YYYY-MM-DD]

Environment:
  DB_PASSWORD_KEY  Passphrase used by openssl for decrypt.
EOF
}

parse_args() {
  DB_PROPS="env.properties"
  DATA_PROPS="export_jobs.properties"
  JOBS_ARG=""
  RUN_DATE=""
  SHOW_HELP=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --db-props)
        DB_PROPS="$2"
        shift 2
        ;;
      --db-profile)
        DB_PROFILE="$2"
        shift 2
        ;;
      --data-props)
        DATA_PROPS="$2"
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
      -h|--help)
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

init_runtime_dates() {
  local run_date="$1"
  if [[ -z "$run_date" ]]; then
    run_date="$(date +%F)"
  fi
  export EXPORT_DATE="$run_date"
  export TODAY="$EXPORT_DATE"
  export YESTERDAY="$(date -d "$EXPORT_DATE -1 day" +%F)"
  export EXPORT_MONTH="$(date -d "$EXPORT_DATE" +%Y-%m)"
  export MONTH_START="$(date -d "$EXPORT_DATE" +%Y-%m-01)"
  export MONTH_END="$(date -d "$MONTH_START +1 month -1 day" +%F)"
}

load_db_config() {
  # Uses lib/db_config.sh which sources properties internally.
  load_properties "$DB_PROPS"
  if [[ -z "${DB_PROFILE:-}" ]]; then
    DB_PROFILE="primary"
  fi
  load_db_profile "$DB_PROFILE"
}

load_job_config_file() {
  # Uses lib/job_config.sh which sources properties internally.
  load_properties "$DATA_PROPS"
}

resolve_jobs() {
  if [[ -n "$JOBS_ARG" ]]; then
    IFS=',' read -r -a JOBS_LIST <<< "$JOBS_ARG"
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

    # Load per-job settings and filters from properties.
    load_job_config "$job"
    load_job_filters "$job"

    # Switch DB profile if job overrides it.
    if [[ -n "$DATA_DB_PROFILE" && "$DATA_DB_PROFILE" != "$DB_PROFILE" ]]; then
      DB_PROFILE="$DATA_DB_PROFILE"
      load_db_profile "$DB_PROFILE"
    fi

    SQL="$(build_select_sql)"

    echo "== Job: $job =="
    echo "DB_PROFILE=$DB_PROFILE"
    echo "SQL=$SQL"
    echo "EXPORT_FILE=${DATA_EXPORT_FILE:-}"
    echo

    # TODO: wire sql_exec once the execution flow is finalized.
  done
}

main() {
  parse_args "$@"
  if [[ "$SHOW_HELP" -eq 1 ]]; then
    return 0
  fi
  init_runtime_dates "$RUN_DATE"
  load_db_config
  load_job_config_file
  resolve_jobs
  run_jobs
}

main "$@"
