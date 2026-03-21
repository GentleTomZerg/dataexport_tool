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

declare -Ag DB

## Load and validate DB_* env vars for a named profile.
## All 7 fields are required. Also verifies that the password key file
## and encrypted password file exist and are readable.
##
## Required keys:
##   <profile>.DB_HOST, <profile>.DB_PORT, <profile>.DB_NAME,
##   <profile>.DB_USER, <profile>.DB_TYPE, <profile>.DB_PASSWORD_DIR,
##   <profile>.DB_PASSWORD_KEY_FILE
##
## Populates the DB associative array.
## Usage: load_db_profile "primary"
load_db_profile() {
  local profile="$1"

  DB[profile]="$profile"
  DB[host]="$(get_prop "${profile}.DB_HOST")"
  DB[port]="$(get_prop "${profile}.DB_PORT")"
  DB[name]="$(get_prop "${profile}.DB_NAME")"
  DB[user]="$(get_prop "${profile}.DB_USER")"
  DB[type]="$(get_prop "${profile}.DB_TYPE")"
  DB[password_key_file]="$(get_prop "${profile}.DB_PASSWORD_KEY_FILE")"

  if [[ -z "${DB[host]}" || -z "${DB[port]}" || -z "${DB[name]}" || -z "${DB[user]}" ]]; then
    echo "Missing DB config for profile: $profile (need HOST, PORT, NAME, USER)" >&2
    return 1
  fi
  if [[ -z "${DB[type]}" ]]; then
    echo "Missing DB_TYPE for profile: $profile" >&2
    return 1
  fi
  if [[ -z "$(get_prop "${profile}.DB_PASSWORD_DIR")" ]]; then
    echo "Missing DB_PASSWORD_DIR for profile: $profile" >&2
    return 1
  fi
  if [[ -z "${DB[password_key_file]}" ]]; then
    echo "Missing DB_PASSWORD_KEY_FILE for profile: $profile" >&2
    return 1
  fi
  if [[ ! -f "${DB[password_key_file]}" ]]; then
    echo "DB_PASSWORD_KEY_FILE not found: ${DB[password_key_file]}" >&2
    return 1
  fi

  DB[password_file]="$(db_password_file)"
  if [[ ! -f "${DB[password_file]}" ]]; then
    echo "DB_PASSWORD_FILE not found: ${DB[password_file]}" >&2
    return 1
  fi
  if [[ ! -r "${DB[password_file]}" ]]; then
    echo "DB_PASSWORD_FILE is not readable: ${DB[password_file]}" >&2
    return 1
  fi

  export DB
}

## Build the encrypted password file path based on current DB values.
## Format: {<profile>.DB_PASSWORD_DIR}/{DB_HOST}_{DB_PORT}_{DB_USER}.pwd
## Usage: path="$(db_password_file)"
db_password_file() {
  local dir
  dir="$(get_prop "${DB[profile]}.DB_PASSWORD_DIR")"
  printf '%s/%s_%s_%s.pwd' "$dir" "${DB[host]}" "${DB[port]}" "${DB[user]}"
}
