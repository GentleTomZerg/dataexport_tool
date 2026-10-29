#!/usr/bin/env bash

decrypt_password_file() {
  local pwd_file="$1"
  local key_file="$2"
  local decrypted

  if [[ ! -f "$key_file" ]]; then
    printf 'ERROR: key file not found: %s\n' "$key_file" >&2
    return 1
  fi
  if [[ ! -f "$pwd_file" ]]; then
    printf 'ERROR: password file not found: %s\n' "$pwd_file" >&2
    return 1
  fi

  decrypted="$(openssl des3 -d -salt -in "$pwd_file" -pass "file:$key_file" -pbkdf2 -iter 100000 2>&1)" || {
    printf 'ERROR: failed to decrypt password file: %s\n' "$decrypted" >&2
    return 1
  }
  printf '%s' "$decrypted"
}

write_encrypted_password() {
  local plain="$1"
  local out_file="$2"
  local key_file="$3"

  if [[ ! -f "$key_file" ]]; then
    printf 'ERROR: key file not found: %s\n' "$key_file" >&2
    return 1
  fi

  mkdir -p "$(dirname "$out_file")"
  printf '%s' "$plain" | openssl des3 -salt -in /dev/stdin -out "$out_file" -pass "file:$key_file" -pbkdf2 -iter 100000
  printf 'Wrote password file: %s\n' "$out_file"
}
