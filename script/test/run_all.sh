#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/test/properties_test.sh"
"$ROOT_DIR/test/db_config_test.sh"
"$ROOT_DIR/test/crypto_test.sh"
"$ROOT_DIR/test/job_config_test.sh"
"$ROOT_DIR/test/sql_builder_test.sh"
"$ROOT_DIR/test/export_data_test.sh"
"$ROOT_DIR/test/sql_exec_test.sh"
"$ROOT_DIR/test/export_exec_test.sh"
"$ROOT_DIR/test/post_export_test.sh"

echo "OK: all tests"
