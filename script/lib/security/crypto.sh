#!/usr/bin/env bash

decrypt_password_file() {
  local pwd_file="$1"
  local profile_name="$2"
  local -n _profile="$profile_name"

  if [[ -z "${_profile[password_key_file]:-}" || ! -f "${_profile[password_key_file]}" ]]; then
    printf 'ERROR: key file not found: %s\n' "${_profile[password_key_file]:-}" >&2
    return 1
  fi
  if [[ ! -f "$pwd_file" ]]; then
    printf 'ERROR: password file not found: %s\n' "$pwd_file" >&2
    return 1
  fi

  openssl des3 -d -salt -in "$pwd_file" -pass "file:${_profile[password_key_file]}" -pbkdf2 -iter 100000
}

write_encrypted_password() {
  local plain="$1"
  local out_file="$2"
  local profile_name="$3"
  local -n _profile="$profile_name"

  if [[ -z "${_profile[password_key_file]:-}" || ! -f "${_profile[password_key_file]}" ]]; then
    printf 'ERROR: key file not found: %s\n' "${_profile[password_key_file]:-}" >&2
    return 1
  fi

  mkdir -p "$(dirname "$out_file")"
  printf '%s' "$plain" | openssl des3 -salt -in /dev/stdin -out "$out_file" -pass "file:${_profile[password_key_file]}" -pbkdf2 -iter 100000
  printf 'Wrote password file: %s\n' "$out_file"
}
