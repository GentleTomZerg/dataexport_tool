#!/usr/bin/env bash
set -euo pipefail

# Create script.zip from the contents of script/
(
  cd script
  zip -r ../data.zip .
)
