#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This script requires bash." >&2
  exit 1
fi
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/db_config.sh"
source "$ROOT_DIR/lib/crypto.sh"

usage() {
  cat <<'USAGE'
Usage:
  password_tool.sh [--db-props file] [--db-profile name] --password value --key-file path

Notes:
- --password and --key-file are required (no interactive prompts).
- Password file location is derived from DB_PASSWORD_DIR and DB profile fields.
- The key file must exist; encryption uses openssl.
USAGE
}

parse_args() {
  DB_PROPS="$ROOT_DIR/etc/local/env.properties"
  DB_PROFILE="primary"
  INPUT_PASSWORD=""
  INPUT_KEY_FILE=""

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
      --password)
        INPUT_PASSWORD="$2"
        shift 2
        ;;
      --key-file)
        INPUT_KEY_FILE="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown arg: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  load_properties "$DB_PROPS"
  load_db_profile "$DB_PROFILE"

  if [[ -z "$INPUT_PASSWORD" || -z "$INPUT_KEY_FILE" ]]; then
    echo "Password and key file are required." >&2
    usage >&2
    exit 1
  fi

  DB_PASSWORD_KEY_FILE="$INPUT_KEY_FILE"
  export DB_PASSWORD_KEY_FILE

  local out_file
  out_file="$(write_db_password_file "$INPUT_PASSWORD")"
  echo "Wrote password file: $out_file"
}

main "$@"
