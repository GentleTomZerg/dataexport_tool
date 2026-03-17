#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This library requires bash." >&2
  return 1 2>/dev/null || exit 1
fi
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
  local raw="${PROPS[$key]:-}"
  printf '%s' "$(expand_value "$raw")"
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

## Expand ${VAR} placeholders using current environment variables.
## Usage: expanded="$(expand_value "path/${EXPORT_DATE}")"
expand_value() {
  local value="$1"
  local var_name var_token var_value
  local i

  for i in {1..10}; do
    if [[ "$value" =~ (\$\{[A-Za-z_][A-Za-z0-9_\\.]*\}) ]]; then
      var_token="${BASH_REMATCH[1]}"
      var_name="${var_token:2:${#var_token}-3}"
      if [[ "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        var_value="${!var_name:-}"
      else
        var_value=""
      fi
      if [[ -z "$var_value" ]]; then
        var_value="${PROPS[$var_name]:-}"
      fi
      value="${value//$var_token/$var_value}"
    else
      break
    fi
  done

  printf '%s' "$value"
}
