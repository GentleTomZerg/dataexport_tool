#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/crypto.sh"

read_profile_password() {
  local profile_name="$1"
  local -n _profile="$profile_name"

  if [[ -z "${_profile[password_file]:-}" || ! -f "${_profile[password_file]}" ]]; then
    printf '%s' ""
    return 0
  fi

  decrypt_password_file "${_profile[password_file]}" "$profile_name"
}
