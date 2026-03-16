#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

status=0

for test_file in "$ROOT_DIR/tests"/test_*.sh; do
  echo "Running $(basename "$test_file")"
  if ! bash "$test_file"; then
    status=1
  fi
done

exit "$status"
