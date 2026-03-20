#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tests=(
  "properties_test.sh"
  "db_config_test.sh"
  "crypto_test.sh"
  "job_config_test.sh"
  "sql_builder_test.sh"
  "sql_exec_test.sh"
  "export_exec_test.sh"
  "post_export_test.sh"
  "export_data_test.sh"
)

failed=()
for t in "${tests[@]}"; do
  if ! "$ROOT_DIR/test/$t"; then
    failed+=("$t")
  fi
done

if [[ "${#failed[@]}" -gt 0 ]]; then
  echo "FAIL: ${#failed[@]} test(s) failed: ${failed[*]}" >&2
  exit 1
fi

echo "OK: all tests"
