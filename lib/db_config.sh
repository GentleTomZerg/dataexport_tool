#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This library requires bash." >&2
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

# Self-contained: load properties helper when sourced directly.
_DBCFG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DBCFG_DIR/properties.sh"
unset _DBCFG_DIR

## Load DB_* env vars for a named profile.
## Required keys: <profile>.DB_HOST, <profile>.DB_PORT, <profile>.DB_NAME, <profile>.DB_USER
## Optional keys: DB_PASSWORD_DIR (defaults to ./secrets)
## Usage: load_db_profile "primary"
load_db_profile() {
  local profile="$1"

  DB_HOST="$(get_prop "${profile}.DB_HOST")"
  DB_PORT="$(get_prop "${profile}.DB_PORT")"
  DB_NAME="$(get_prop "${profile}.DB_NAME")"
  DB_USER="$(get_prop "${profile}.DB_USER")"
  DB_TYPE="$(get_prop "${profile}.DB_TYPE")"
  [[ -z "$DB_TYPE" ]] && DB_TYPE="mysql"

  if [[ -z "$DB_HOST" || -z "$DB_PORT" || -z "$DB_NAME" || -z "$DB_USER" ]]; then
    echo "Missing DB config for profile: $profile" >&2
    return 1
  fi

  DB_PASSWORD_FILE="$(db_password_file)"

  export DB_HOST DB_PORT DB_NAME DB_USER DB_TYPE DB_PASSWORD_FILE
}

## Build the encrypted password file path based on current DB_* values.
## Format: {DB_PASSWORD_DIR}/{DB_HOST}_{DB_PORT}_{DB_USER}.pwd
## Usage: path="$(db_password_file)"
db_password_file() {
  local dir
  dir="$(get_prop "DB_PASSWORD_DIR")"
  [[ -z "$dir" ]] && dir="./secrets"
  printf '%s/%s_%s_%s.pwd' "$dir" "$DB_HOST" "$DB_PORT" "$DB_USER"
}
