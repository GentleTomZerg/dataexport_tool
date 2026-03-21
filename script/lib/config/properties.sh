#!/usr/bin/env bash

trim() {
  local s="$1"
  s="${s##+([[:space:]])}"
  s="${s%%+([[:space:]])}"
  printf '%s' "$s"
}

load_props_from_file() {
  local file="$1"
  local map_name="$2"
  local -n _map="$map_name"
  local key value

  if [[ ! -f "$file" ]]; then
    printf 'ERROR: properties file not found: %s\n' "$file" >&2
    return 1
  fi

  while IFS=$'\t' read -r key value || [[ -n "${key:-}" ]]; do
    [[ -z "${key:-}" ]] && continue
    _map["$key"]="$value"
  done < <(
    awk '
      {
        sub(/\r$/, "", $0)
        line=$0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line == "" || line ~ /^#/ || line ~ /^;/) next
        pos = index(line, "=")
        if (pos == 0) {
          key = line
          val = ""
        } else {
          key = substr(line, 1, pos - 1)
          val = substr(line, pos + 1)
        }
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        if (key != "") print key "\t" val
      }
    ' "$file"
  )
}

props_keys() {
  local map_name="$1"
  local prefix="$2"
  local -n _map="$map_name"
  local key

  for key in "${!_map[@]}"; do
    [[ "$key" == "$prefix"* ]] && printf '%s\n' "$key"
  done
}

expand_value() {
  local map_name="$1"
  local raw="$2"
  local -n _map="$map_name"
  local value="$raw"
  local token name resolved i

  for i in {1..20}; do
    if [[ "$value" =~ (\$\{[A-Za-z_][A-Za-z0-9_.]*\}) ]]; then
      token="${BASH_REMATCH[1]}"
      name="${token:2:${#token}-3}"
      if [[ "$name" != *.* && ${!name+x} ]]; then
        resolved="${!name}"
      elif [[ -n "${_map[$name]+x}" ]]; then
        resolved="${_map[$name]}"
      else
        resolved=""
      fi
      value="${value//$token/$resolved}"
    else
      break
    fi
  done

  printf '%s' "$value"
}

props_get() {
  local map_name="$1"
  local key="$2"
  local -n _map="$map_name"
  printf '%s' "$(expand_value "$map_name" "${_map[$key]:-}")"
}
