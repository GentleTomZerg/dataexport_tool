#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This library requires bash." >&2
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail
shopt -s extglob

## Trim leading/trailing whitespace from a string.
## Usage: trimmed="$(trim "  value  ")"
trim() {
  local s="$1"
  s="${s##+([[:space:]])}"
  s="${s%%+([[:space:]])}"
  printf '%s' "$s"
}
