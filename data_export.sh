#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This script requires bash. Run: bash data_export.sh ..." >&2
  exit 1
fi
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$ROOT_DIR/lib/properties.sh"
source "$ROOT_DIR/lib/db_profile.sh"
source "$ROOT_DIR/lib/crypto.sh"
source "$ROOT_DIR/lib/export_config.sh"
source "$ROOT_DIR/lib/sql_builder.sh"
source "$ROOT_DIR/lib/sql_exec.sh"

usage() {
  cat <<'EOF'
Usage:
  ./data_export.sh [--db-props file] [--db-profile name] [--data-props file] [--job name|--jobs a,b] [--date YYYY-MM-DD]

Environment:
  DB_PASSWORD_KEY  Passphrase used by openssl for decrypt.
EOF
}

main() {
  local db_props="env.properties"
  local data_props="data_export.properties"
  local jobs_arg=""
  local run_date=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --db-props)
        db_props="$2"
        shift 2
        ;;
      --db-profile)
        DB_PROFILE="$2"
        shift 2
        ;;
      --data-props)
        data_props="$2"
        shift 2
        ;;
      --job)
        jobs_arg="$2"
        shift 2
        ;;
      --jobs)
        jobs_arg="$2"
        shift 2
        ;;
      --date)
        run_date="$2"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        echo "Unknown arg: $1" >&2
        usage >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$run_date" ]]; then
    run_date="$(date +%F)"
  fi
  export EXPORT_DATE="$run_date"
  export TODAY="$EXPORT_DATE"
  export YESTERDAY="$(date -d "$EXPORT_DATE -1 day" +%F)"
  export EXPORT_MONTH="$(date -d "$EXPORT_DATE" +%Y-%m)"
  export MONTH_START="$(date -d "$EXPORT_DATE" +%Y-%m-01)"
  export MONTH_END="$(date -d "$EXPORT_DATE +1 month -1 day" +%F)"

  # Load DB config
  load_properties "$db_props"
  if [[ -z "${DB_PROFILE:-}" ]]; then
    DB_PROFILE="primary"
  fi
  load_db_profile "$DB_PROFILE"

  # Load data config
  load_properties "$data_props"

  if [[ -n "$jobs_arg" ]]; then
    IFS=',' read -r -a JOBS_LIST <<< "$jobs_arg"
  else
    mapfile -t JOBS_LIST < <(list_jobs)
  fi

  if [[ "${#JOBS_LIST[@]}" -eq 0 ]]; then
    echo "No jobs specified. Use --job/--jobs or set JOBS in data_export.properties." >&2
    return 1
  fi

  for job in "${JOBS_LIST[@]}"; do
    job="${job##+([[:space:]])}"
    job="${job%%+([[:space:]])}"
    [[ -z "$job" ]] && continue

    load_job_config "$job"
    load_job_filters "$job"

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
  done
}

main "$@"
