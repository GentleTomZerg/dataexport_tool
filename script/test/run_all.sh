#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tests=(
  properties_test.sh
  selector_test.sh
  plan_test.sh
  exportctl_test.sh
)

for t in "${tests[@]}"; do
  "$ROOT_DIR/test/$t"
done

echo "OK: all tests"
