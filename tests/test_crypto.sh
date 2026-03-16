#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/crypto.sh"
source "$ROOT_DIR/tests/helpers.sh"

tmp_dir="$(tempdir)"
pwd_file="$tmp_dir/127.0.0.1_5432_user1.pwd"

export DB_PASSWORD_KEY="test-key-123"

encode_password "secret" "$pwd_file"
assert_file_exists "$pwd_file"

decoded="$(decrypt_password "$pwd_file")"
assert_eq "secret" "$decoded" "decrypt_password"
