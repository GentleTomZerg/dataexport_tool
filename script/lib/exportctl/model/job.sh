#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/properties.sh"

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

validate_split_config() {
  local job_name="$1"
  local split_col="$2"
  local chunk_size="$3"
  local chunks="$4"
  local -n _columns_seen="$5"

  if [[ -z "$chunk_size" || -z "$chunks" ]]; then
    printf 'ERROR: invalid split config for job %s column %s\n' "$job_name" "$split_col" >&2
    return 1
  fi
  if [[ ! "$chunk_size" =~ ^[0-9]+$ || ! "$chunks" =~ ^[0-9]+$ || "$chunk_size" -le 0 || "$chunks" -le 0 ]]; then
    printf 'ERROR: invalid split numbers for job %s column %s\n' "$job_name" "$split_col" >&2
    return 1
  fi
  if [[ -z "${_columns_seen[$split_col]:-}" ]]; then
    printf 'ERROR: split column %s is not present in COLUMNS for job %s\n' "$split_col" "$job_name" >&2
    return 1
  fi
  return 0
}

extract_job_fields() {
  local props_name="$1"
  local job_name="$2"
  local out_name="$3"
  local -n _out="$out_name"
  local prefix="job.${job_name}."

  _out[name]="$job_name"
  _out[db_type]="$(props_get "$props_name" "${prefix}DB_TYPE")"
  _out[db_host]="$(props_get "$props_name" "${prefix}DB_HOST")"
  _out[db_port]="$(props_get "$props_name" "${prefix}DB_PORT")"
  _out[db_name]="$(props_get "$props_name" "${prefix}DB_NAME")"
  _out[db_user]="$(props_get "$props_name" "${prefix}DB_USER")"
  _out[password_file]="$(props_get "$props_name" "${prefix}DB_PASSWORD_FILE")"
  _out[password_key_file]="$(props_get "$props_name" "${prefix}DB_PASSWORD_KEY_FILE")"
  _out[table]="$(props_get "$props_name" "${prefix}TABLE_NAME")"
  _out[columns]="$(props_get "$props_name" "${prefix}COLUMNS")"
  _out[where]="$(props_get "$props_name" "${prefix}WHERE")"
  _out[export_file]="$(props_get "$props_name" "${prefix}EXPORT_FILE")"
  _out[field_separator]="$(props_get "$props_name" "${prefix}FIELD_SEPARATOR")"
  _out[line_terminator]="$(props_get "$props_name" "${prefix}LINE_TERMINATOR")"
  _out[field_separator_data_replacement]="$(props_get "$props_name" "${prefix}FIELD_SEPARATOR_DATA_REPLACEMENT")"
  _out[compress_enabled]="$(props_get "$props_name" "${prefix}COMPRESS.ENABLED")"
  _out[compress_mode]="$(props_get "$props_name" "${prefix}COMPRESS.MODE")"
  _out[compress_overwrite]="$(props_get "$props_name" "${prefix}COMPRESS.OVERWRITE")"
  _out[compress_remove_original]="$(props_get "$props_name" "${prefix}COMPRESS.REMOVE_ORIGINAL")"
  _out[transfer_enabled]="$(props_get "$props_name" "${prefix}TRANSFER.ENABLED")"
  _out[transfer_dir]="$(props_get "$props_name" "${prefix}TRANSFER.DIR")"
  _out[transfer_mode]="$(props_get "$props_name" "${prefix}TRANSFER.MODE")"
  _out[transfer_overwrite]="$(props_get "$props_name" "${prefix}TRANSFER.OVERWRITE")"
  _out[transfer_rename]="$(props_get "$props_name" "${prefix}TRANSFER.RENAME")"
}

apply_job_defaults() {
  local out_name="$1"
  local -n _out="$out_name"

  [[ -n "${_out[field_separator]}" ]] || _out[field_separator]='\t'
  [[ -n "${_out[line_terminator]}" ]] || _out[line_terminator]='\n'
  [[ -n "${_out[field_separator_data_replacement]}" ]] || _out[field_separator_data_replacement]='|?'
  [[ -n "${_out[compress_enabled]}" ]] || _out[compress_enabled]='false'
  [[ -n "${_out[compress_mode]}" ]] || _out[compress_mode]='tar.gz'
  [[ -n "${_out[compress_overwrite]}" ]] || _out[compress_overwrite]='false'
  [[ -n "${_out[compress_remove_original]}" ]] || _out[compress_remove_original]='false'
  _out[transfer_enabled]="${_out[transfer_enabled]:-false}"
  _out[transfer_mode]="${_out[transfer_mode]:-move}"
  _out[transfer_overwrite]="${_out[transfer_overwrite]:-false}"
  _out[splits]=""
}

validate_required_fields() {
  local out_name="$1"
  local job_name="$2"
  local -n _out="$out_name"

  local missing=""
  [[ -z "${_out[db_type]:-}" ]] && missing="DB_TYPE"
  [[ -z "${_out[db_host]:-}" ]] && missing="$missing DB_HOST"
  [[ -z "${_out[db_port]:-}" ]] && missing="$missing DB_PORT"
  [[ -z "${_out[db_name]:-}" ]] && missing="$missing DB_NAME"
  [[ -z "${_out[db_user]:-}" ]] && missing="$missing DB_USER"
  [[ -z "${_out[password_file]:-}" ]] && missing="$missing DB_PASSWORD_FILE"
  [[ -z "${_out[password_key_file]:-}" ]] && missing="$missing DB_PASSWORD_KEY_FILE"
  [[ -z "${_out[table]:-}" ]] && missing="$missing TABLE_NAME"
  [[ -z "${_out[columns]:-}" ]] && missing="$missing COLUMNS"

  if [[ -n "$missing" ]]; then
    printf 'ERROR: invalid job %s missing required fields: %s\n' "$job_name" "$missing" >&2
    return 1
  fi
  return 0
}

parse_job_splits() {
  local props_name="$1"
  local job_name="$2"
  local out_name="$3"
  local columns_str="${4:-}"
  local -n _out="$out_name"
  local prefix="job.${job_name}."
  local split_key split_col split_value chunk_size chunks extra
  local -A columns_seen=()
  local col

  local -a cols=()
  IFS=',' read -r -a cols <<<"$columns_str"
  for col in "${cols[@]}"; do
    col="$(trim "$col")"
    [[ -n "$col" ]] && columns_seen["$col"]=1
  done

  while IFS= read -r split_key; do
    split_col="${split_key#${prefix}SPLIT.}"
    split_value="$(props_get "$props_name" "$split_key")"
    IFS=',' read -r chunk_size chunks extra <<<"$split_value"
    chunk_size="$(trim "${chunk_size:-}")"
    chunks="$(trim "${chunks:-}")"

    if [[ -n "${extra:-}" ]]; then
      printf 'ERROR: invalid split config for job %s column %s\n' "$job_name" "$split_col" >&2
      return 1
    fi

    validate_split_config "$job_name" "$split_col" "$chunk_size" "$chunks" columns_seen || return 1

    [[ -n "${_out[splits]}" ]] && _out[splits]+=$'\n'
    _out[splits]+="${split_col}|${chunk_size}|${chunks}"
  done < <(props_keys "$props_name" "${prefix}SPLIT.")
}

load_export_job() {
  local props_name="$1"
  local job_name="$2"
  local out_name="$3"
  local -n _out="$out_name"

  extract_job_fields "$props_name" "$job_name" "$out_name"
  apply_job_defaults "$out_name"
  validate_required_fields "$out_name" "$job_name" || return 1

  parse_job_splits "$props_name" "$job_name" "$out_name" "${_out[columns]}" || return 1
}
