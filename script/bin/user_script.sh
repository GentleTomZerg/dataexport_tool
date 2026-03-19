#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage:
  user_script.sh <YYYY-MM-DD>

Notes:
  - This wrapper is POSIX sh compatible.
  - export_data.sh is always executed with bash.
  - The single argument maps to export_data.sh --date.
  - Update DB_CONFIG and JOBS_CONFIG below if your paths differ.

export_data.sh flags:
  --db-props <file>
  --db-profile <name>
  --data-props <file>
  --job <name>
  --jobs <a,b>
  --date <YYYY-MM-DD>
  --execute
  -h, --help
USAGE
}

main() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ $# -ne 1 ]; then
    usage
    [ $# -eq 1 ] && return 0
    return 1
  fi

  batch_date="$1"

  SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
  ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

  # Default locations (edit here if you keep configs elsewhere).
  DB_CONFIG="$ROOT_DIR/etc/local/env.properties"
  JOBS_CONFIG="$ROOT_DIR/etc/local/config/export_jobs.properties"

  exec bash "$ROOT_DIR/bin/export_data.sh" \
    --db-config "$DB_CONFIG" \
    --jobs-config "$JOBS_CONFIG" \
    --date "$batch_date"
}

main "$@"
