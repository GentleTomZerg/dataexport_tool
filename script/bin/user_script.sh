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
  - Update CONFIG_FILE below if your paths differ.
  - ENV_CONFIG is optional; only needed if ENV_* variables are referenced.
  - Set FAKE_MYSQL=1 to use a stub mysql client for testing.

export_data.sh flags:
  --db-config <file>
  --jobs-config <file>
  --env-config <file>
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
  CONFIG_FILE="$ROOT_DIR/etc/local/config/export_jobs_where.properties"
  ENV_CONFIG="$ROOT_DIR/etc/local/env.properties"

  FAKE_MYSQL=0

  if [ "${FAKE_MYSQL:-0}" = "1" ]; then
    FAKE_BIN=$(mktemp -d)
    trap 'rm -rf "$FAKE_BIN"' EXIT
    cat >"$FAKE_BIN/mysql" <<'FAKE'
#!/bin/sh
set -eu
# Emit tab-separated rows (no header), similar to mysql --batch --raw --skip-column-names.
printf '1\tAlice\n2\tBob\n'
FAKE
    chmod +x "$FAKE_BIN/mysql"
    PATH="$FAKE_BIN:$PATH"
  fi

  exec bash "$ROOT_DIR/bin/export_data.sh" \
    --db-config "$CONFIG_FILE" \
    --jobs-config "$CONFIG_FILE" \
    --env-config "$ENV_CONFIG" \
    --date "$batch_date"
}

main "$@"
