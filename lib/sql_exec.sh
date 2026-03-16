#!/usr/bin/env bash
set -euo pipefail

## Execute SQL and export results to file using the selected DB_TYPE.
## Currently supports: postgres
## Usage: sql_exec_export "$sql" "/path/to/output.csv"
sql_exec_export() {
  local sql="$1"
  local out_file="$2"
  local db_type="${DB_TYPE:-postgres}"

  if [[ -z "$out_file" ]]; then
    echo "Missing export output file path" >&2
    return 1
  fi

  case "$db_type" in
    postgres)
      if [[ -z "${DB_PASSWORD:-}" ]]; then
        echo "DB_PASSWORD is not set" >&2
        return 1
      fi
      PGPASSWORD="$DB_PASSWORD" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -c "\\copy (${sql}) TO '${out_file}' CSV HEADER"
      ;;
    *)
      echo "Unsupported DB_TYPE: $db_type" >&2
      return 1
      ;;
  esac
}
