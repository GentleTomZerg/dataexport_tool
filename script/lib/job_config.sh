#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This library requires bash." >&2
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

# Self-contained: load properties helper when sourced directly.
_JOB_CFG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_JOB_CFG_DIR/properties.sh"
unset _JOB_CFG_DIR

## List job names.
## Discover names from keys like: job.<name>.* in the loaded properties.
## Order is sorted to keep output stable for tests and CLI usage.
## Usage: list_jobs
list_jobs() {
  local key name
  declare -A seen

  while IFS= read -r key; do
    name="${key#job.}"
    name="${name%%.*}"
    [[ -z "$name" ]] && continue
    seen["$name"]=1
  done < <(list_props_by_prefix "job.")

  for name in "${!seen[@]}"; do
    printf '%s\n' "$name"
  done | sort
}

## Load a single export job configuration from PROPS.
## Required keys: job.<name>.TABLE_NAME, job.<name>.COLUMNS
## Optional keys: job.<name>.DB_PROFILE, job.<name>.EXPORT_FILE,
##                job.<name>.FIELD_SEPARATOR, job.<name>.LINE_TERMINATOR,
##                job.<name>.FILTER.*, job.<name>.SPLIT.<col>
## Usage: load_job_config "job1"
load_job_config() {
  local job="$1"
  local prefix="job.${job}."

  JOB_NAME="$job"
  JOB_DB_PROFILE="$(get_prop "${prefix}DB_PROFILE")"
  JOB_TABLE="$(get_prop "${prefix}TABLE_NAME")"
  JOB_COLUMNS="$(get_prop "${prefix}COLUMNS")"
  JOB_EXPORT_FILE="$(get_prop "${prefix}EXPORT_FILE")"
  JOB_FIELD_SEPARATOR="$(get_prop "${prefix}FIELD_SEPARATOR")"
  JOB_LINE_TERMINATOR="$(get_prop "${prefix}LINE_TERMINATOR")"

  [[ -z "$JOB_FIELD_SEPARATOR" ]] && JOB_FIELD_SEPARATOR="\\t"
  [[ -z "$JOB_LINE_TERMINATOR" ]] && JOB_LINE_TERMINATOR="\\n"

  if [[ -z "$JOB_TABLE" || -z "$JOB_COLUMNS" ]]; then
    echo "Missing TABLE_NAME or COLUMNS for job: $job" >&2
    return 1
  fi

  export JOB_NAME JOB_DB_PROFILE JOB_TABLE JOB_COLUMNS JOB_EXPORT_FILE
  export JOB_FIELD_SEPARATOR JOB_LINE_TERMINATOR
}

## Collect split column definitions for a job into JOB_SPLITS array.
##
## Split properties (export_jobs.properties), Option B:
##   job.<name>.SPLIT.<col>=<chunk_size>,<chunks>
##
## Output structure (JOB_SPLITS):
## - "col|chunk_size|chunks"
##
## Notes:
## - Only columns listed in JOB_COLUMNS are actually split.
## - Invalid or incomplete split values are ignored.
load_job_splits() {
  local job="$1"
  local prefix="job.${job}.SPLIT."
  JOB_SPLITS=()
  local key col value chunk_size chunks extra

  while IFS= read -r key; do
    col="${key#${prefix}}"
    [[ -z "$col" ]] && continue
    value="$(get_prop "$key")"
    IFS=',' read -r chunk_size chunks extra <<<"$value"
    chunk_size="$(trim "${chunk_size:-}")"
    chunks="$(trim "${chunks:-}")"

    [[ "$chunk_size" =~ ^[0-9]+$ ]] || continue
    [[ "$chunks" =~ ^[0-9]+$ ]] || continue
    [[ "$chunk_size" -gt 0 ]] || continue
    [[ "$chunks" -gt 0 ]] || continue

    JOB_SPLITS+=("${col}|${chunk_size}|${chunks}")
  done < <(list_props_by_prefix "$prefix")

  export JOB_SPLITS
}

## Collect filter definitions for a job into JOB_FILTERS array.
##
## Filter properties (export_jobs.properties):
## - Basic:
##   job.<name>.FILTER.<col>=value
## - With operator:
##   job.<name>.FILTER.<col>.value=value
##   job.<name>.FILTER.<col>.op=LIKE
## - BETWEEN:
##   job.<name>.FILTER.<col>.op=BETWEEN
##   job.<name>.FILTER.<col>.from=2024-01-01
##   job.<name>.FILTER.<col>.to=2024-01-31
##
## Output structure (JOB_FILTERS):
## - "col|op|value" (single value; op defaults to '=')
## - "col|BETWEEN|from|to" (range)
##
## Notes:
## - BETWEEN requires both .from and .to; missing values become empty strings.
## - The resulting array order follows property iteration order and is not stable.
## This normalized array is consumed by lib/sql_builder.sh.
load_job_filters() {
  local job="$1"
  local prefix="job.${job}.FILTER."
  JOB_FILTERS=()
  local key col op value

  while IFS= read -r key; do
    if [[ "$key" =~ ^job\.${job}\.FILTER\.([^\.]+)\.value$ ]]; then
      col="${BASH_REMATCH[1]}"
      value="$(get_prop "$key")"
      op="$(get_prop "job.${job}.FILTER.${col}.op")"
      [[ -z "$op" ]] && op="="
      JOB_FILTERS+=("${col}|${op}|${value}")
    elif [[ "$key" =~ ^job\.${job}\.FILTER\.([^\.]+)\.from$ ]]; then
      col="${BASH_REMATCH[1]}"
      op="$(get_prop "job.${job}.FILTER.${col}.op")"
      [[ "${op^^}" != "BETWEEN" ]] && continue
      local from to
      from="$(get_prop "job.${job}.FILTER.${col}.from")"
      to="$(get_prop "job.${job}.FILTER.${col}.to")"
      JOB_FILTERS+=("${col}|BETWEEN|${from}|${to}")
    elif [[ "$key" =~ ^job\.${job}\.FILTER\.([^\.]+)$ ]]; then
      col="${BASH_REMATCH[1]}"
      value="$(get_prop "$key")"
      op="="
      JOB_FILTERS+=("${col}|${op}|${value}")
    fi
  done < <(list_props_by_prefix "$prefix")

  export JOB_FILTERS
}
