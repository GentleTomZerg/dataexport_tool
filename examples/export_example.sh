#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/properties.sh"
source "$ROOT_DIR/lib/db_profile.sh"
source "$ROOT_DIR/lib/crypto.sh"
source "$ROOT_DIR/lib/export_config.sh"
source "$ROOT_DIR/lib/sql_builder.sh"
source "$ROOT_DIR/lib/sql_exec.sh"

DB_PROPS="$ROOT_DIR/env.properties"
DATA_PROPS="$ROOT_DIR/data_export.properties"

load_properties "$DB_PROPS"
DB_PROFILE="primary"
load_db_profile "$DB_PROFILE"

load_properties "$DATA_PROPS"
mapfile -t JOBS_LIST < <(list_jobs)

for job in "${JOBS_LIST[@]}"; do
  load_job_config "$job"
  load_job_filters "$job"

  if [[ -n "$DATA_DB_PROFILE" && "$DATA_DB_PROFILE" != "$DB_PROFILE" ]]; then
    DB_PROFILE="$DATA_DB_PROFILE"
    load_db_profile "$DB_PROFILE"
  fi

  SQL="$(build_select_sql)"
  echo "== Job: $job =="
  echo "SQL=$SQL"
  echo
done
