#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/test/test_helpers.sh"
source "$ROOT_DIR/lib/properties.sh"

# Use a temp workspace so tests don't touch project files.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROPS_FILE="$TMP_DIR/test.properties"
cat >"$PROPS_FILE" <<'PROPS'
# Comment line
; Another comment line

  key1 = value1
key2=   value2  
key3=    
key4=${ENV_VAL}
key5=${prop.with.dots}
prop.with.dots=dotty
nested.a=${nested.b}
nested.b=${nested.c}
nested.c=final
win.line=ok

job.users.name=alice
job.users.role=admin
job.orders.name=bob
PROPS

# Load properties and verify raw storage.
load_properties "$PROPS_FILE"
assert_eq "value1" "${PROPS[key1]}" "trim spaces around key/value"
assert_eq "value2" "${PROPS[key2]}" "trim trailing spaces"
assert_eq "" "${PROPS[key3]}" "allow empty values"

# list_props_by_prefix should return only matching keys.
mapfile -t keys < <(list_props_by_prefix "job.users.")
assert_true "[[ ${#keys[@]} -eq 2 ]]" "list_props_by_prefix count"

# Expansion: env has priority even if empty.
ENV_VAL="env-value"
export ENV_VAL
assert_eq "env-value" "$(get_prop key4)" "env overrides property"

ENV_VAL=""
export ENV_VAL
assert_eq "" "$(get_prop key4)" "empty env overrides property"

unset ENV_VAL
assert_eq "" "$(get_prop key4)" "unset env falls back to props (unset here)"

# Expansion: dotted keys should resolve from PROPS.
assert_eq "dotty" "$(get_prop key5)" "resolve dotted key from PROPS"

# Expansion: nested properties should resolve through multiple passes.
assert_eq "final" "$(get_prop nested.a)" "nested expansion"

# Unknown placeholder resolves to empty string.
PROPS[unknown]='${DOES_NOT_EXIST}'
assert_eq "" "$(get_prop unknown)" "unknown var resolves to empty"

# Windows CR should be stripped.
assert_eq "ok" "${PROPS[win.line]}" "strip CR from lines"

echo "OK: properties_test.sh"
