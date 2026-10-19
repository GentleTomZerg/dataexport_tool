#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/credentials.sh"

_sanitize_fields() {
  local replacement="$1"
  awk -v FS='\t' -v OFS='\t' -v REPLACEMENT="$replacement" '
    BEGIN{
      replacement = REPLACEMENT
      gsub(/&/, "\\&", replacement)
    }
    {
      for (i=1; i<=NF; i++) {
        if ($i == "NULL") $i = "";
        gsub(/\|!/, replacement, $i);
      }
      $1=$1; print
    }
  '
}

_apply_separators() {
  local field_sep_raw="$1"
  local line_term_raw="$2"

  awk -v FS='\t' -v OFS_RAW="$field_sep_raw" -v ORS_RAW="$line_term_raw" '
    BEGIN{
      OFS=OFS_RAW; ORS=ORS_RAW;
      gsub(/\\t/,"\t",OFS); gsub(/\\n/,"\n",OFS); gsub(/\\r/,"\r",OFS);
      gsub(/\\t/,"\t",ORS); gsub(/\\n/,"\n",ORS); gsub(/\\r/,"\r",ORS);
    }
    {
      $1=$1; print
    }
  '
}

execute_plan_export() {
  local plan_name="$1"
  local -n _plan="$plan_name"
  local password
  local error_file

  mkdir -p "$(dirname "${_plan[export_file]}")" || return 1
  password="$(read_plan_password "$plan_name")" || return 1
  error_file="$(mktemp)"

  case "${_plan[db_type]}" in
  mysql)
    MYSQL_PWD="$password" mysql --batch --raw --skip-column-names \
      -h "${_plan[db_host]}" \
      -P "${_plan[db_port]}" \
      -u "${_plan[db_user]}" \
      "${_plan[db_name]}" \
      -e "${_plan[sql]}" 2>"$error_file" |
      _sanitize_fields "${_plan[field_separator_data_replacement]}" |
      _apply_separators "${_plan[field_separator]}" "${_plan[line_terminator]}" >"${_plan[export_file]}"
    ;;
  postgres)
    PGPASSWORD="$password" psql \
      -h "${_plan[db_host]}" \
      -p "${_plan[db_port]}" \
      -U "${_plan[db_user]}" \
      -d "${_plan[db_name]}" \
      -c "\\copy (${_plan[sql]}) TO STDOUT WITH (FORMAT text, DELIMITER E'\\t')" 2>"$error_file" |
      _sanitize_fields "${_plan[field_separator_data_replacement]}" |
      _apply_separators "${_plan[field_separator]}" "${_plan[line_terminator]}" >"${_plan[export_file]}"
    ;;
  *)
    rm -f "$error_file"
    printf 'ERROR: unsupported DB type: %s\n' "${_plan[db_type]}" >&2
    return 1
    ;;
  esac

  local -a pipeline_status=("${PIPESTATUS[@]}")
  local db_exit_code=${pipeline_status[0]:-1}
  local sanitize_exit_code=${pipeline_status[1]:-1}
  local format_exit_code=${pipeline_status[2]:-1}
  if [[ "$db_exit_code" -ne 0 ]]; then
    printf 'ERROR: %s failed for %s: %s\n' "${_plan[db_type]}" "${_plan[db_name]}" "$(cat "$error_file")" >&2
    rm -f "$error_file"
    return 1
  fi
  if [[ "$sanitize_exit_code" -ne 0 || "$format_exit_code" -ne 0 ]]; then
    rm -f "$error_file"
    printf 'ERROR: transform pipeline failed for %s export\n' "${_plan[db_name]}" >&2
    return 1
  fi

  rm -f "$error_file"
}
