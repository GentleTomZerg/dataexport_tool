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
##                job.<name>.FILTER.*, job.<name>.SPLIT.<col>,
##                job.<name>.TRANSFER.*, job.<name>.COMPRESS.*
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

  if [[ -z "$JOB_FIELD_SEPARATOR" ]]; then
    JOB_FIELD_SEPARATOR="\\t"
  fi
  if [[ -z "$JOB_LINE_TERMINATOR" ]]; then
    JOB_LINE_TERMINATOR="\\n"
  fi

  if [[ -z "$JOB_TABLE" || -z "$JOB_COLUMNS" ]]; then
    echo "Missing TABLE_NAME or COLUMNS for job: $job" >&2
    return 1
  fi

  export JOB_NAME JOB_DB_PROFILE JOB_TABLE JOB_COLUMNS JOB_EXPORT_FILE
  export JOB_FIELD_SEPARATOR JOB_LINE_TERMINATOR
}

## Validate job columns and separators after load_job_config.
## - Columns must be non-empty after trimming.
## - Separators must be non-empty.
validate_job_config() {
  local job="$1"
  local raw_columns=()
  local col trimmed

  if [[ -z "$JOB_FIELD_SEPARATOR" ]]; then
    echo "Empty FIELD_SEPARATOR for job: $job" >&2
    return 1
  fi
  if [[ -z "$JOB_LINE_TERMINATOR" ]]; then
    echo "Empty LINE_TERMINATOR for job: $job" >&2
    return 1
  fi

  IFS=',' read -r -a raw_columns <<<"$JOB_COLUMNS"
  for col in "${raw_columns[@]}"; do
    trimmed="$(trim "$col")"
    if [[ -z "$trimmed" ]]; then
      echo "Invalid COLUMNS for job: $job (empty column name)" >&2
      return 1
    fi
  done
}

## Load transfer settings into JOB_TRANSFER_* variables.
## Defaults:
## - ENABLED=false
## - MODE=move
## - OVERWRITE=false
## - RENAME=""
load_job_transfer() {
  local job="$1"
  local prefix="job.${job}.TRANSFER."

  JOB_TRANSFER_ENABLED="$(get_prop "${prefix}ENABLED")"
  JOB_TRANSFER_DIR="$(get_prop "${prefix}DIR")"
  JOB_TRANSFER_MODE="$(get_prop "${prefix}MODE")"
  JOB_TRANSFER_OVERWRITE="$(get_prop "${prefix}OVERWRITE")"
  JOB_TRANSFER_RENAME="$(get_prop "${prefix}RENAME")"

  JOB_TRANSFER_ENABLED="${JOB_TRANSFER_ENABLED,,}"
  JOB_TRANSFER_MODE="${JOB_TRANSFER_MODE,,}"
  JOB_TRANSFER_OVERWRITE="${JOB_TRANSFER_OVERWRITE,,}"

  if [[ -z "$JOB_TRANSFER_ENABLED" ]]; then
    JOB_TRANSFER_ENABLED="false"
  fi
  if [[ -z "$JOB_TRANSFER_MODE" ]]; then
    JOB_TRANSFER_MODE="move"
  fi
  if [[ -z "$JOB_TRANSFER_OVERWRITE" ]]; then
    JOB_TRANSFER_OVERWRITE="false"
  fi
}

validate_job_transfer() {
  local job="$1"
  if [[ "$JOB_TRANSFER_ENABLED" == "true" ]]; then
    if [[ -z "$JOB_TRANSFER_DIR" ]]; then
      echo "Missing TRANSFER.DIR for job: $job" >&2
      return 1
    fi
    case "$JOB_TRANSFER_MODE" in
      move|copy)
        ;;
      *)
        echo "Invalid TRANSFER.MODE for job: $job ($JOB_TRANSFER_MODE)" >&2
        return 1
        ;;
    esac
    case "$JOB_TRANSFER_OVERWRITE" in
      true|false)
        ;;
      *)
        echo "Invalid TRANSFER.OVERWRITE for job: $job ($JOB_TRANSFER_OVERWRITE)" >&2
        return 1
        ;;
    esac
  fi
}

## Load compression settings into JOB_COMPRESS_* variables.
## Defaults:
## - ENABLED=false
## - MODE=tar.gz
## - OVERWRITE=false
## - REMOVE_ORIGINAL=false
load_job_compress() {
  local job="$1"
  local prefix="job.${job}.COMPRESS."

  JOB_COMPRESS_ENABLED="$(get_prop "${prefix}ENABLED")"
  JOB_COMPRESS_MODE="$(get_prop "${prefix}MODE")"
  JOB_COMPRESS_OVERWRITE="$(get_prop "${prefix}OVERWRITE")"
  JOB_COMPRESS_REMOVE_ORIGINAL="$(get_prop "${prefix}REMOVE_ORIGINAL")"

  JOB_COMPRESS_ENABLED="${JOB_COMPRESS_ENABLED,,}"
  JOB_COMPRESS_MODE="${JOB_COMPRESS_MODE,,}"
  JOB_COMPRESS_OVERWRITE="${JOB_COMPRESS_OVERWRITE,,}"
  JOB_COMPRESS_REMOVE_ORIGINAL="${JOB_COMPRESS_REMOVE_ORIGINAL,,}"

  if [[ -z "$JOB_COMPRESS_ENABLED" ]]; then
    JOB_COMPRESS_ENABLED="false"
  fi
  if [[ -z "$JOB_COMPRESS_MODE" ]]; then
    JOB_COMPRESS_MODE="tar.gz"
  fi
  if [[ -z "$JOB_COMPRESS_OVERWRITE" ]]; then
    JOB_COMPRESS_OVERWRITE="false"
  fi
  if [[ -z "$JOB_COMPRESS_REMOVE_ORIGINAL" ]]; then
    JOB_COMPRESS_REMOVE_ORIGINAL="false"
  fi
}

validate_job_compress() {
  local job="$1"
  if [[ "$JOB_COMPRESS_ENABLED" == "true" ]]; then
    case "$JOB_COMPRESS_MODE" in
      gz|tar|tar.gz|tgz)
        ;;
      *)
        echo "Invalid COMPRESS.MODE for job: $job ($JOB_COMPRESS_MODE)" >&2
        return 1
        ;;
    esac
    case "$JOB_COMPRESS_OVERWRITE" in
      true|false)
        ;;
      *)
        echo "Invalid COMPRESS.OVERWRITE for job: $job ($JOB_COMPRESS_OVERWRITE)" >&2
        return 1
        ;;
    esac
    case "$JOB_COMPRESS_REMOVE_ORIGINAL" in
      true|false)
        ;;
      *)
        echo "Invalid COMPRESS.REMOVE_ORIGINAL for job: $job ($JOB_COMPRESS_REMOVE_ORIGINAL)" >&2
        return 1
        ;;
    esac
  fi
}

## Collect split column definitions for a job into JOB_SPLITS_RAW array.
##
## Split properties (export_jobs.properties), Option B:
##   job.<name>.SPLIT.<col>=<chunk_size>,<chunks>
##
## Output structure (JOB_SPLITS_RAW):
## - "col|chunk_size|chunks|extra"
##
## Notes:
## - Only columns listed in JOB_COLUMNS are actually split.
## - Validation is handled by validate_job_splits().
load_job_splits() {
  local job="$1"
  local prefix="job.${job}.SPLIT."
  JOB_SPLITS_RAW=()
  local key col value chunk_size chunks extra

  while IFS= read -r key; do
    col="${key#${prefix}}"
    [[ -z "$col" ]] && continue
    value="$(get_prop "$key")"
    IFS=',' read -r chunk_size chunks extra <<<"$value"
    chunk_size="$(trim "${chunk_size:-}")"
    chunks="$(trim "${chunks:-}")"
    JOB_SPLITS_RAW+=("${col}|${chunk_size}|${chunks}|${extra}")
  done < <(list_props_by_prefix "$prefix")

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

}

## Validate split rules and produce JOB_SPLITS for SQL building.
validate_job_splits() {
  local job="$1"
  local raw_columns=()
  local col_name
  declare -A columns_set

  IFS=',' read -r -a raw_columns <<<"$JOB_COLUMNS"
  for col_name in "${raw_columns[@]}"; do
    col_name="$(trim "$col_name")"
    [[ -z "$col_name" ]] && continue
    columns_set["$col_name"]=1
  done

  JOB_SPLITS=()
  local item col chunk_size chunks extra
  for item in "${JOB_SPLITS_RAW[@]:-}"; do
    [[ -z "$item" ]] && continue
    IFS='|' read -r col chunk_size chunks extra <<<"$item"

    if [[ -z "$chunk_size" || -z "$chunks" ]]; then
      echo "Invalid SPLIT for job: $job (empty value for $col)" >&2
      return 1
    fi
    if [[ -n "$extra" ]]; then
      echo "Invalid SPLIT for job: $job (too many parts for $col)" >&2
      return 1
    fi
    if [[ ! "$chunk_size" =~ ^[0-9]+$ || ! "$chunks" =~ ^[0-9]+$ ]]; then
      echo "Invalid SPLIT for job: $job ($col expects <chunk_size>,<chunks>)" >&2
      return 1
    fi
    if [[ "$chunk_size" -le 0 || "$chunks" -le 0 ]]; then
      echo "Invalid SPLIT for job: $job ($col expects positive integers)" >&2
      return 1
    fi
    if [[ -z "${columns_set[$col]:-}" ]]; then
      echo "Invalid SPLIT for job: $job (column not in COLUMNS: $col)" >&2
      return 1
    fi

    JOB_SPLITS+=("${col}|${chunk_size}|${chunks}")
  done

}
## Validate filter definitions that require extra fields.
## - BETWEEN must have both .from and .to values.
validate_job_filters() {
  local job="$1"
  local prefix="job.${job}.FILTER."
  local key col op from to

  while IFS= read -r key; do
    if [[ "$key" =~ ^job\.${job}\.FILTER\.([^\.]+)\.op$ ]]; then
      col="${BASH_REMATCH[1]}"
      op="$(get_prop "$key")"
      if [[ "${op^^}" == "BETWEEN" ]]; then
        from="$(get_prop "${prefix}${col}.from")"
        to="$(get_prop "${prefix}${col}.to")"
        if [[ -z "$from" || -z "$to" ]]; then
          echo "Invalid BETWEEN filter for job: $job (missing from/to for $col)" >&2
          return 1
        fi
      fi
    fi
  done < <(list_props_by_prefix "$prefix")
}
