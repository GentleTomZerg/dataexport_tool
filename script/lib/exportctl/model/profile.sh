#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/properties.sh"

load_export_profile() {
  local props_name="$1"
  local profile_name="$2"
  local out_name="$3"
  local -n _props="$props_name"
  local -n _out="$out_name"
  local key

  _out[profile]="$profile_name"

  if [[ "$profile_name" == ENV_* ]]; then
    _out[host]="$(props_get "$props_name" "${profile_name}_HOST")"
    _out[port]="$(props_get "$props_name" "${profile_name}_PORT")"
    _out[name]="$(props_get "$props_name" "${profile_name}_NAME")"
    _out[user]="$(props_get "$props_name" "${profile_name}_USER")"
    _out[type]="$(props_get "$props_name" "${profile_name}_TYPE")"
    _out[password_key_file]="$(props_get "$props_name" "${profile_name}_PASSWORD_KEY_FILE")"
    _out[password_file]="$(props_get "$props_name" "${profile_name}_PASSWORD_FILE")"
  else
    _out[host]="$(props_get "$props_name" "${profile_name}.DB_HOST")"
    _out[port]="$(props_get "$props_name" "${profile_name}.DB_PORT")"
    _out[name]="$(props_get "$props_name" "${profile_name}.DB_NAME")"
    _out[user]="$(props_get "$props_name" "${profile_name}.DB_USER")"
    _out[type]="$(props_get "$props_name" "${profile_name}.DB_TYPE")"
    _out[password_key_file]="$(props_get "$props_name" "${profile_name}.DB_PASSWORD_KEY_FILE")"
    _out[password_file]="$(props_get "$props_name" "${profile_name}.DB_PASSWORD_FILE")"
  fi

  for key in host port name user type password_file password_key_file; do
    if [[ -z "${_out[$key]:-}" ]]; then
      printf 'ERROR: incomplete DB profile %s missing %s\n' "$profile_name" "$key" >&2
      return 1
    fi
  done
}
