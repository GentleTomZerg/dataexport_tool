#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/config/properties.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/test.properties" <<'EOF'
key1 = value1
key2=${ENV_VAL}
job.users.name=alice
EOF

declare -A PROPS=()
load_props_from_file "$TMP_DIR/test.properties" PROPS
assert_eq "value1" "${PROPS[key1]}" "raw value"
ENV_VAL="from_env"
export ENV_VAL
assert_eq "from_env" "$(props_get PROPS key2)" "env expansion"
mapfile -t keys < <(props_keys PROPS "job.")
assert_eq "1" "${#keys[@]}" "job key count"

echo "OK: properties_test.sh"
