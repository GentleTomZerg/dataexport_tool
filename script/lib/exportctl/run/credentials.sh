#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/crypto.sh"

read_profile_password() {
  local profile_name="$1"
  local -n _profile="$profile_name"
  local decrypted

  if [[ -z "${_profile[password_file]:-}" ]]; then
    printf 'ERROR: password_file not configured for profile\n' >&2
    return 1
  fi
  if [[ ! -f "${_profile[password_file]}" ]]; then
    printf 'ERROR: password file not found: %s\n' "${_profile[password_file]}" >&2
    return 1
  fi

  decrypted="$(decrypt_password_file "${_profile[password_file]}" "${_profile[password_key_file]}")" || return 1
  if [[ -z "$decrypted" ]]; then
    printf 'ERROR: password file is empty or decrypt failed: %s\n' "${_profile[password_file]}" >&2
    return 1
  fi

  printf '%s' "$decrypted"
}
