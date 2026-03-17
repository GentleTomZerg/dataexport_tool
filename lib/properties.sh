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

## Resolve a placeholder name to a value.
## Precedence:
## 1) Environment variables (even if empty)
## 2) Properties map
## 3) Empty string
## Usage: resolved="$(resolve_var "VAR_NAME")"
resolve_var() {
  local name="$1"
  if [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    # If the env var is set (even to empty), it wins.
    if [[ ${!name+x} ]]; then
      printf '%s' "${!name}"
      return
    fi
  fi
  printf '%s' "${PROPS[$name]:-}"
}

## Load key/value pairs from a .properties file into PROPS.
## Lines starting with '#' are ignored. Keys and values are trimmed.
## Usage: load_properties path/to/env.properties
load_properties() {
  local file="$1"
  local line key value

  if [[ ! -f "$file" ]]; then
    echo "Properties file not found: $file" >&2
    return 1
  fi

  # Use awk for parsing to keep the Bash loop clean and predictable.
  # Scope: key=value only, trim spaces, ignore blank lines and #/; comments.
  while IFS=$'\t' read -r key value || [[ -n "$key" ]]; do
    [[ -z "$key" ]] && continue
    PROPS["$key"]="$value"
  done < <(
    awk -F'=' '
      {
        sub(/\r$/, "", $0)
        line=$0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line == "" || line ~ /^#/ || line ~ /^;/) next
        key=$1
        $1=""
        sub(/^=/, "", $0)
        val=$0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        if (key != "") print key "\t" val
      }
    ' "$file"
  )
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

  # Replace one token per pass to allow nested expansions.
  for i in {1..10}; do
    if [[ "$value" =~ (\$\{[A-Za-z_][A-Za-z0-9_\\.]*\}) ]]; then
      var_token="${BASH_REMATCH[1]}"
      var_name="${var_token:2:${#var_token}-3}"
      var_value="$(resolve_var "$var_name")"
      value="${value//$var_token/$var_value}"
    else
      break
    fi
  done

  printf '%s' "$value"
}
