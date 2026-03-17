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

## List job names from JOBS property (comma-separated).
## Usage: list_jobs
list_jobs() {
  local jobs
  jobs="$(get_prop "JOBS")"
  [[ -z "$jobs" ]] && return 0
  echo "$jobs" | tr ',' '\n' | awk '{$1=$1};1'
}

## Load a single export job configuration from PROPS.
## Required keys: job.<name>.TABLE_NAME, job.<name>.COLUMNS
## Optional keys: job.<name>.DB_PROFILE, job.<name>.EXPORT_FILE, job.<name>.FILTER.*
## Usage: load_job_config "job1"
load_job_config() {
  local job="$1"
  local prefix="job.${job}."

  DATA_JOB="$job"
  DATA_DB_PROFILE="$(get_prop "${prefix}DB_PROFILE")"
  DATA_TABLE="$(get_prop "${prefix}TABLE_NAME")"
  DATA_COLUMNS="$(get_prop "${prefix}COLUMNS")"
  DATA_EXPORT_FILE="$(get_prop "${prefix}EXPORT_FILE")"

  if [[ -z "$DATA_TABLE" || -z "$DATA_COLUMNS" ]]; then
    echo "Missing TABLE_NAME or COLUMNS for job: $job" >&2
    return 1
  fi

  export DATA_JOB DATA_DB_PROFILE DATA_TABLE DATA_COLUMNS DATA_EXPORT_FILE
}

## Collect filter definitions for a job into DATA_FILTERS array.
##
## Filter properties (data_export.properties):
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
## Output structure (DATA_FILTERS):
## - "col|op|value" (single value; op defaults to '=')
## - "col|BETWEEN|from|to" (range)
##
## This normalized array is consumed by lib/sql_builder.sh.
load_job_filters() {
  local job="$1"
  local prefix="job.${job}.FILTER."
  DATA_FILTERS=()
  local key col op value

  while IFS= read -r key; do
    if [[ "$key" =~ ^job\.${job}\.FILTER\.([^\.]+)\.value$ ]]; then
      col="${BASH_REMATCH[1]}"
      value="$(get_prop "$key")"
      op="$(get_prop "job.${job}.FILTER.${col}.op")"
      [[ -z "$op" ]] && op="="
      DATA_FILTERS+=("${col}|${op}|${value}")
    elif [[ "$key" =~ ^job\.${job}\.FILTER\.([^\.]+)\.from$ ]]; then
      col="${BASH_REMATCH[1]}"
      op="$(get_prop "job.${job}.FILTER.${col}.op")"
      [[ "${op^^}" != "BETWEEN" ]] && continue
      local from to
      from="$(get_prop "job.${job}.FILTER.${col}.from")"
      to="$(get_prop "job.${job}.FILTER.${col}.to")"
      DATA_FILTERS+=("${col}|BETWEEN|${from}|${to}")
    elif [[ "$key" =~ ^job\.${job}\.FILTER\.([^\.]+)$ ]]; then
      col="${BASH_REMATCH[1]}"
      value="$(get_prop "$key")"
      op="="
      DATA_FILTERS+=("${col}|${op}|${value}")
    fi
  done < <(list_props_by_prefix "$prefix")

  export DATA_FILTERS
}
