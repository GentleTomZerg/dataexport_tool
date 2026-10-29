#!/usr/bin/env bash

require_bash() {
  if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "This project requires bash." >&2
    return 1
  fi
}

setup_shell() {
  require_bash || exit 1
  set -uo pipefail
  shopt -s extglob
}
