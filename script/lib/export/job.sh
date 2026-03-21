#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/properties.sh"

list_export_jobs() {
  local props_name="$1"
  local key name
  declare -A seen=()

  while IFS= read -r key; do
    name="${key#job.}"
    name="${name%%.*}"
    [[ -n "$name" ]] && seen["$name"]=1
  done < <(props_keys "$props_name" "job.")

  for name in "${!seen[@]}"; do
    printf '%s\n' "$name"
  done | sort
}

load_export_job() {
  local props_name="$1"
  local job_name="$2"
  local out_name="$3"
  local -n _out="$out_name"
  local prefix="job.${job_name}."
  local split_key split_col split_value chunk_size chunks extra col
  local -a raw_columns=()
  declare -A columns_seen=()

  _out[name]="$job_name"
  _out[db_profile]="$(props_get "$props_name" "${prefix}DB_PROFILE")"
  _out[table]="$(props_get "$props_name" "${prefix}TABLE_NAME")"
  _out[columns]="$(props_get "$props_name" "${prefix}COLUMNS")"
  _out[where]="$(props_get "$props_name" "${prefix}WHERE")"
  _out[export_file]="$(props_get "$props_name" "${prefix}EXPORT_FILE")"
  _out[field_separator]="$(props_get "$props_name" "${prefix}FIELD_SEPARATOR")"
  _out[line_terminator]="$(props_get "$props_name" "${prefix}LINE_TERMINATOR")"
  _out[groups]="$(props_get "$props_name" "${prefix}GROUPS")"
  _out[compress_enabled]="$(props_get "$props_name" "${prefix}COMPRESS.ENABLED")"
  _out[compress_mode]="$(props_get "$props_name" "${prefix}COMPRESS.MODE")"
  _out[compress_overwrite]="$(props_get "$props_name" "${prefix}COMPRESS.OVERWRITE")"
  _out[compress_remove_original]="$(props_get "$props_name" "${prefix}COMPRESS.REMOVE_ORIGINAL")"
  _out[transfer_enabled]="$(props_get "$props_name" "${prefix}TRANSFER.ENABLED")"
  _out[transfer_dir]="$(props_get "$props_name" "${prefix}TRANSFER.DIR")"
  _out[transfer_mode]="$(props_get "$props_name" "${prefix}TRANSFER.MODE")"
  _out[transfer_overwrite]="$(props_get "$props_name" "${prefix}TRANSFER.OVERWRITE")"
  _out[transfer_rename]="$(props_get "$props_name" "${prefix}TRANSFER.RENAME")"

  [[ -n "${_out[field_separator]}" ]] || _out[field_separator]='\t'
  [[ -n "${_out[line_terminator]}" ]] || _out[line_terminator]='\n'
  [[ -n "${_out[compress_enabled]}" ]] || _out[compress_enabled]='false'
  [[ -n "${_out[compress_mode]}" ]] || _out[compress_mode]='tar.gz'
  [[ -n "${_out[compress_overwrite]}" ]] || _out[compress_overwrite]='false'
  [[ -n "${_out[compress_remove_original]}" ]] || _out[compress_remove_original]='false'
  [[ -n "${_out[transfer_enabled]}" ]] || _out[transfer_enabled]='false'
  [[ -n "${_out[transfer_mode]}" ]] || _out[transfer_mode]='move'
  [[ -n "${_out[transfer_overwrite]}" ]] || _out[transfer_overwrite]='false'
  _out[splits]=""

  if [[ -z "${_out[db_profile]}" || -z "${_out[table]}" || -z "${_out[columns]}" ]]; then
    printf 'ERROR: invalid job %s missing required fields\n' "$job_name" >&2
    return 1
  fi

  IFS=',' read -r -a raw_columns <<<"${_out[columns]}"
  for col in "${raw_columns[@]}"; do
    col="$(trim "$col")"
    [[ -n "$col" ]] && columns_seen["$col"]=1
  done

  while IFS= read -r split_key; do
    split_col="${split_key#${prefix}SPLIT.}"
    split_value="$(props_get "$props_name" "$split_key")"
    IFS=',' read -r chunk_size chunks extra <<<"$split_value"
    chunk_size="$(trim "${chunk_size:-}")"
    chunks="$(trim "${chunks:-}")"

    if [[ -z "$chunk_size" || -z "$chunks" || -n "${extra:-}" ]]; then
      printf 'ERROR: invalid split config for job %s column %s\n' "$job_name" "$split_col" >&2
      return 1
    fi
    if [[ ! "$chunk_size" =~ ^[0-9]+$ || ! "$chunks" =~ ^[0-9]+$ || "$chunk_size" -le 0 || "$chunks" -le 0 ]]; then
      printf 'ERROR: invalid split numbers for job %s column %s\n' "$job_name" "$split_col" >&2
      return 1
    fi
    if [[ -z "${columns_seen[$split_col]:-}" ]]; then
      printf 'ERROR: split column %s is not present in COLUMNS for job %s\n' "$split_col" "$job_name" >&2
      return 1
    fi

    if [[ -n "${_out[splits]}" ]]; then
      _out[splits]+=$'\n'
    fi
    _out[splits]+="${split_col}|${chunk_size}|${chunks}"
  done < <(props_keys "$props_name" "${prefix}SPLIT.")
}
