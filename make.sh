#!/usr/bin/env bash
set -euo pipefail

# Create script.zip from the contents of script/
(
  cd script
  zip -r ../script.zip .
)

# Base64-encode script.zip to script.txt
base64 script.zip >script.txt

# Send the file using Prometheus tool
~/stow/tools/Prometheus/prometheus.sh send_file script.txt
