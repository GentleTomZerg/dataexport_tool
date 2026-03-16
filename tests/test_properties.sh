#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/properties.sh"
source "$ROOT_DIR/tests/helpers.sh"

tmp_dir="$(tempdir)"
props_file="$tmp_dir/test.properties"

cat <<'EOF' > "$props_file"
# comment
FOO = bar
EMPTY=
  BAZ=qux
EOF

load_properties "$props_file"

assert_eq "bar" "$(get_prop "FOO")" "FOO"
assert_eq "" "$(get_prop "EMPTY")" "EMPTY"
assert_eq "qux" "$(get_prop "BAZ")" "BAZ"
