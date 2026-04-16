#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/crypto.sh"

read_plan_password() {
  local plan_name="$1"
  local -n _plan="$plan_name"
  local decrypted

  if [[ -z "${_plan[password_file]:-}" ]]; then
    printf 'ERROR: password_file not configured for job\n' >&2
    return 1
  fi
  if [[ ! -f "${_plan[password_file]}" ]]; then
    printf 'ERROR: password file not found: %s\n' "${_plan[password_file]}" >&2
    return 1
  fi

  decrypted="$(decrypt_password_file "${_plan[password_file]}" "${_plan[password_key_file]}")" || return 1
  if [[ -z "$decrypted" ]]; then
    printf 'ERROR: password file is empty or decrypt failed: %s\n' "${_plan[password_file]}" >&2
    return 1
  fi

  printf '%s' "$decrypted"
}
