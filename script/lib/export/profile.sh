#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/properties.sh"

profile_password_file() {
  local props_name="$1"
  local profile_name="$2"
  local db_name="$3"
  local -n _props="$props_name"
  local -n _db="$db_name"

  printf '%s/%s_%s_%s.pwd' \
    "${_props[${profile_name}.DB_PASSWORD_DIR]:-}" \
    "${_db[host]}" \
    "${_db[port]}" \
    "${_db[user]}"
}

load_export_profile() {
  local props_name="$1"
  local profile_name="$2"
  local out_name="$3"
  local -n _props="$props_name"
  local -n _out="$out_name"
  local key

  _out[profile]="$profile_name"
  _out[host]="$(props_get "$props_name" "${profile_name}.DB_HOST")"
  _out[port]="$(props_get "$props_name" "${profile_name}.DB_PORT")"
  _out[name]="$(props_get "$props_name" "${profile_name}.DB_NAME")"
  _out[user]="$(props_get "$props_name" "${profile_name}.DB_USER")"
  _out[type]="$(props_get "$props_name" "${profile_name}.DB_TYPE")"
  _out[password_dir]="$(props_get "$props_name" "${profile_name}.DB_PASSWORD_DIR")"
  _out[password_key_file]="$(props_get "$props_name" "${profile_name}.DB_PASSWORD_KEY_FILE")"

  for key in host port name user type password_dir password_key_file; do
    if [[ -z "${_out[$key]:-}" ]]; then
      printf 'ERROR: incomplete DB profile %s missing %s\n' "$profile_name" "$key" >&2
      return 1
    fi
  done

  _out[password_file]="$(profile_password_file "$props_name" "$profile_name" "$out_name")"
}
