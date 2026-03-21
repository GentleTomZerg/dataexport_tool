#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This library requires bash." >&2
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

## Decrypt password file using openssl and DB_PASSWORD_KEY_FILE (path to key file).
## Requires: openssl on PATH and a readable key file.
## Usage: plain="$(decrypt_password "/path/to/file.pwd")"
decrypt_password() {
  local pwd_file="$1"

  if [[ -z "${DB[password_key_file]:-}" ]]; then
    echo "DB[password_key_file] is not set. It is required to decrypt passwords." >&2
    return 1
  fi
  if [[ ! -f "$pwd_file" ]]; then
    echo "Password file not found: $pwd_file" >&2
    return 1
  fi
  if [[ ! -f "${DB[password_key_file]}" ]]; then
    echo "Key file not found: ${DB[password_key_file]}" >&2
    return 1
  fi

  openssl des3 -d -salt -in "$pwd_file" -pass "file:${DB[password_key_file]}" -pbkdf2 -iter 100000
}

## Encrypt a plaintext password into a .pwd file using openssl and DB_PASSWORD_KEY_FILE.
## Creates the parent directory for the output file if needed.
## Usage: encode_password "plain" "/path/to/file.pwd"
encode_password() {
  local plain="$1"
  local pwd_file="$2"

  if [[ -z "${DB[password_key_file]:-}" ]]; then
    echo "DB[password_key_file] is not set. It is required to encrypt passwords." >&2
    return 1
  fi
  if [[ ! -f "${DB[password_key_file]}" ]]; then
    echo "Key file not found: ${DB[password_key_file]}" >&2
    return 1
  fi

  mkdir -p "$(dirname "$pwd_file")"
  printf '%s' "$plain" | openssl des3 -salt -in /dev/stdin -out "$pwd_file" -pass "file:${DB[password_key_file]}" -pbkdf2 -iter 100000
}

## Encrypt a plaintext password into the profile-based .pwd file.
## Requires db_password_file() from lib/db_config.sh.
## Usage: write_db_password_file "plain"
write_db_password_file() {
  local plain="$1"
  local pwd_file

  if ! declare -F db_password_file >/dev/null 2>&1; then
    echo "db_password_file is not available; source lib/db_config.sh before writing password files." >&2
    return 1
  fi

  pwd_file="$(db_password_file)"
  encode_password "$plain" "$pwd_file"
  printf '%s' "$pwd_file"
}
