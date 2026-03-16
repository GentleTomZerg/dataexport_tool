#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

declare -Ag PROPS

## Trim leading/trailing whitespace from a string.
## Usage: trimmed="$(trim "  value  ")"
trim() {
  local s="$1"
  s="${s##+([[:space:]])}"
  s="${s%%+([[:space:]])}"
  printf '%s' "$s"
}

## Load key/value pairs from a .properties file into PROPS.
## Lines starting with '#' are ignored. Keys and values are trimmed.
## Usage: load_properties path/to/env.properties
load_properties() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "Properties file not found: $file" >&2
    return 1
  fi

  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    key="$(trim "$key")"
    value="$(trim "$value")"

    # Skip blanks and comments
    [[ -z "$key" ]] && continue
    [[ "$key" == \#* ]] && continue

    PROPS["$key"]="$value"
  done < "$file"
}

## Read a property value by key.
## Usage: value="$(get_prop "some.key")"
get_prop() {
  local key="$1"
  printf '%s' "${PROPS[$key]:-}"
}

## List property keys by prefix.
## Usage: list_props_by_prefix "FILTER."
list_props_by_prefix() {
  local prefix="$1"
  local key

  for key in "${!PROPS[@]}"; do
    if [[ "$key" == "$prefix"* ]]; then
      printf '%s\n' "$key"
    fi
  done
}
