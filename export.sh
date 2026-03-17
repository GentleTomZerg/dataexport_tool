#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$ROOT_DIR/lib/properties.sh"
source "$ROOT_DIR/lib/db_config.sh"
source "$ROOT_DIR/lib/crypto.sh"

# Example helper that prints DB config from env
print_db_config() {
  echo "DB_PROFILE=$DB_PROFILE"
  echo "DB_HOST=$DB_HOST"
  echo "DB_PORT=$DB_PORT"
  echo "DB_NAME=$DB_NAME"
  echo "DB_USER=$DB_USER"
  echo "DB_PASSWORD_FILE=$(db_password_file)"
}

# Main
usage() {
  cat <<'EOF'
Usage:
  ./export.sh [--props file] [--profile name] <command> [args]

Commands:
  print-config
  encode-password --password 'plain'
  show-password

Environment:
  DB_PASSWORD_KEY  Passphrase used by openssl for encrypt/decrypt.
EOF
}

main() {
  local props_file="env.properties"
  local cmd="print-config"
  local password_plain=""

  DB_PROFILE="primary"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --props)
        props_file="$2"
        shift 2
        ;;
      --profile)
        DB_PROFILE="$2"
        shift 2
        ;;
      encode-password|print-config|show-password)
        cmd="$1"
        shift
        ;;
      --password)
        password_plain="$2"
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

  load_properties "$props_file"
  load_db_profile "$DB_PROFILE"

  case "$cmd" in
    print-config)
      print_db_config
      ;;
    encode-password)
      if [[ -z "$password_plain" ]]; then
        echo "Missing --password" >&2
        return 1
      fi
      encode_password "$password_plain" "$(db_password_file)"
      ;;
    show-password)
      decrypt_password "$(db_password_file)"
      ;;
  esac
}

main "$@"
