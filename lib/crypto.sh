#!/usr/bin/env bash
set -euo pipefail

## Decrypt password file using openssl and DB_PASSWORD_KEY.
## Usage: plain="$(decrypt_password "/path/to/file.pwd")"
decrypt_password() {
  local pwd_file="$1"

  if [[ -z "${DB_PASSWORD_KEY:-}" ]]; then
    echo "DB_PASSWORD_KEY is not set. It is required to decrypt passwords." >&2
    return 1
  fi
  if [[ ! -f "$pwd_file" ]]; then
    echo "Password file not found: $pwd_file" >&2
    return 1
  fi

  openssl enc -aes-256-cbc -d -a -pbkdf2 -pass env:DB_PASSWORD_KEY -in "$pwd_file"
}

## Encrypt a plaintext password into a .pwd file using openssl and DB_PASSWORD_KEY.
## Usage: encode_password "plain" "/path/to/file.pwd"
encode_password() {
  local plain="$1"
  local pwd_file="$2"

  if [[ -z "${DB_PASSWORD_KEY:-}" ]]; then
    echo "DB_PASSWORD_KEY is not set. It is required to encrypt passwords." >&2
    return 1
  fi

  mkdir -p "$(dirname "$pwd_file")"
  printf '%s' "$plain" | openssl enc -aes-256-cbc -a -pbkdf2 -salt -pass env:DB_PASSWORD_KEY -out "$pwd_file"
}
