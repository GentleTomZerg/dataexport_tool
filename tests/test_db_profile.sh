#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/properties.sh"
source "$ROOT_DIR/lib/db_profile.sh"
source "$ROOT_DIR/tests/helpers.sh"

tmp_dir="$(tempdir)"
props_file="$tmp_dir/test.properties"

cat <<'EOF' > "$props_file"
primary.DB_HOST=127.0.0.1
primary.DB_PORT=5432
primary.DB_NAME=example
primary.DB_USER=user1
DB_PASSWORD_DIR=/tmp/secrets
EOF

load_properties "$props_file"
load_db_profile "primary"

assert_eq "127.0.0.1" "$DB_HOST" "DB_HOST"
assert_eq "5432" "$DB_PORT" "DB_PORT"
assert_eq "example" "$DB_NAME" "DB_NAME"
assert_eq "user1" "$DB_USER" "DB_USER"
assert_eq "/tmp/secrets/127.0.0.1_5432_user1.pwd" "$(db_password_file)" "password file"
