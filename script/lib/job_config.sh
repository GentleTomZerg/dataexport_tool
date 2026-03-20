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

declare -Ag JOB
declare -Ag JOB_TRANSFER
declare -Ag JOB_COMPRESS

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
##                job.<name>.WHERE, job.<name>.SPLIT.<col>,
##                job.<name>.TRANSFER.*, job.<name>.COMPRESS.*
## Populates the JOB associative array.
## Usage: load_job_config "job1"
load_job_config() {
  local job="$1"
  local prefix="job.${job}."

  JOB[name]="$job"
  JOB[db_profile]="$(get_prop "${prefix}DB_PROFILE")"
  JOB[table]="$(get_prop "${prefix}TABLE_NAME")"
  JOB[columns]="$(get_prop "${prefix}COLUMNS")"
  JOB[export_file]="$(get_prop "${prefix}EXPORT_FILE")"
  JOB[field_separator]="$(get_prop "${prefix}FIELD_SEPARATOR")"
  JOB[line_terminator]="$(get_prop "${prefix}LINE_TERMINATOR")"
  JOB[where]="$(get_prop "${prefix}WHERE")"

  if [[ -z "${JOB[field_separator]}" ]]; then
    JOB[field_separator]="\\t"
  fi
  if [[ -z "${JOB[line_terminator]}" ]]; then
    JOB[line_terminator]="\\n"
  fi

  if [[ -z "${JOB[table]}" || -z "${JOB[columns]}" ]]; then
    echo "Missing TABLE_NAME or COLUMNS for job: $job" >&2
    return 1
  fi

  export JOB
}

## Validate job columns and separators after load_job_config.
## - Columns must be non-empty after trimming.
## - Separators must be non-empty.
validate_job_config() {
  local job="$1"
  local raw_columns=()
  local col trimmed

  if [[ -z "${JOB[field_separator]}" ]]; then
    echo "Empty FIELD_SEPARATOR for job: $job" >&2
    return 1
  fi
  if [[ -z "${JOB[line_terminator]}" ]]; then
    echo "Empty LINE_TERMINATOR for job: $job" >&2
    return 1
  fi

  IFS=',' read -r -a raw_columns <<<"${JOB[columns]}"
  for col in "${raw_columns[@]}"; do
    trimmed="$(trim "$col")"
    if [[ -z "$trimmed" ]]; then
      echo "Invalid COLUMNS for job: $job (empty column name)" >&2
      return 1
    fi
  done
}

## Load transfer settings into JOB_TRANSFER associative array.
## Defaults:
## - enabled=false
## - mode=move
## - overwrite=false
## - rename=""
load_job_transfer() {
  local job="$1"
  local prefix="job.${job}.TRANSFER."

  JOB_TRANSFER[enabled]="$(get_prop "${prefix}ENABLED")"
  JOB_TRANSFER[dir]="$(get_prop "${prefix}DIR")"
  JOB_TRANSFER[mode]="$(get_prop "${prefix}MODE")"
  JOB_TRANSFER[overwrite]="$(get_prop "${prefix}OVERWRITE")"
  JOB_TRANSFER[rename]="$(get_prop "${prefix}RENAME")"

  JOB_TRANSFER[enabled]="${JOB_TRANSFER[enabled],,}"
  JOB_TRANSFER[mode]="${JOB_TRANSFER[mode],,}"
  JOB_TRANSFER[overwrite]="${JOB_TRANSFER[overwrite],,}"

  if [[ -z "${JOB_TRANSFER[enabled]}" ]]; then
    JOB_TRANSFER[enabled]="false"
  fi
  if [[ -z "${JOB_TRANSFER[mode]}" ]]; then
    JOB_TRANSFER[mode]="move"
  fi
  if [[ -z "${JOB_TRANSFER[overwrite]}" ]]; then
    JOB_TRANSFER[overwrite]="false"
  fi
}

validate_job_transfer() {
  local job="$1"
  if [[ "${JOB_TRANSFER[enabled]}" == "true" ]]; then
    if [[ -z "${JOB_TRANSFER[dir]}" ]]; then
      echo "Missing TRANSFER.DIR for job: $job" >&2
      return 1
    fi
    case "${JOB_TRANSFER[mode]}" in
      move|copy)
        ;;
      *)
        echo "Invalid TRANSFER.MODE for job: $job (${JOB_TRANSFER[mode]})" >&2
        return 1
        ;;
    esac
    case "${JOB_TRANSFER[overwrite]}" in
      true|false)
        ;;
      *)
        echo "Invalid TRANSFER.OVERWRITE for job: $job (${JOB_TRANSFER[overwrite]})" >&2
        return 1
        ;;
    esac
  fi
}

## Load compression settings into JOB_COMPRESS associative array.
## Defaults:
## - enabled=false
## - mode=tar.gz
## - overwrite=false
## - remove_original=false
load_job_compress() {
  local job="$1"
  local prefix="job.${job}.COMPRESS."

  JOB_COMPRESS[enabled]="$(get_prop "${prefix}ENABLED")"
  JOB_COMPRESS[mode]="$(get_prop "${prefix}MODE")"
  JOB_COMPRESS[overwrite]="$(get_prop "${prefix}OVERWRITE")"
  JOB_COMPRESS[remove_original]="$(get_prop "${prefix}REMOVE_ORIGINAL")"

  JOB_COMPRESS[enabled]="${JOB_COMPRESS[enabled],,}"
  JOB_COMPRESS[mode]="${JOB_COMPRESS[mode],,}"
  JOB_COMPRESS[overwrite]="${JOB_COMPRESS[overwrite],,}"
  JOB_COMPRESS[remove_original]="${JOB_COMPRESS[remove_original],,}"

  if [[ -z "${JOB_COMPRESS[enabled]}" ]]; then
    JOB_COMPRESS[enabled]="false"
  fi
  if [[ -z "${JOB_COMPRESS[mode]}" ]]; then
    JOB_COMPRESS[mode]="tar.gz"
  fi
  if [[ -z "${JOB_COMPRESS[overwrite]}" ]]; then
    JOB_COMPRESS[overwrite]="false"
  fi
  if [[ -z "${JOB_COMPRESS[remove_original]}" ]]; then
    JOB_COMPRESS[remove_original]="false"
  fi
}

validate_job_compress() {
  local job="$1"
  if [[ "${JOB_COMPRESS[enabled]}" == "true" ]]; then
    case "${JOB_COMPRESS[mode]}" in
      gz|tar|tar.gz|tgz)
        ;;
      *)
        echo "Invalid COMPRESS.MODE for job: $job (${JOB_COMPRESS[mode]})" >&2
        return 1
        ;;
    esac
    case "${JOB_COMPRESS[overwrite]}" in
      true|false)
        ;;
      *)
        echo "Invalid COMPRESS.OVERWRITE for job: $job (${JOB_COMPRESS[overwrite]})" >&2
        return 1
        ;;
    esac
    case "${JOB_COMPRESS[remove_original]}" in
      true|false)
        ;;
      *)
        echo "Invalid COMPRESS.REMOVE_ORIGINAL for job: $job (${JOB_COMPRESS[remove_original]})" >&2
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
## - Only columns listed in JOB[columns] are actually split.
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

## Validate split rules and produce JOB_SPLITS for SQL building.
validate_job_splits() {
  local job="$1"
  local raw_columns=()
  local col_name
  declare -A columns_set

  IFS=',' read -r -a raw_columns <<<"${JOB[columns]}"
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
