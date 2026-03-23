#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/credentials.sh"

_apply_separators() {
  local field_sep_raw="$1"
  local line_term_raw="$2"

  awk -v FS='\t' -v OFS_RAW="$field_sep_raw" -v ORS_RAW="$line_term_raw" '
    BEGIN{
      OFS=OFS_RAW; ORS=ORS_RAW;
      gsub(/\\t/,"\t",OFS); gsub(/\\n/,"\n",OFS); gsub(/\\r/,"\r",OFS);
      gsub(/\\t/,"\t",ORS); gsub(/\\n/,"\n",ORS); gsub(/\\r/,"\r",ORS);
    }
    { $1=$1; print }
  '
}

execute_plan_export() {
  local plan_name="$1"
  local profile_name="$2"
  local -n _plan="$plan_name"
  local -n _profile="$profile_name"
  local password
  local error_file

  mkdir -p "$(dirname "${_plan[export_file]}")" || return 1
  password="$(read_profile_password "$profile_name")" || return 1
  error_file="$(mktemp)"

  case "${_plan[db_type]}" in
  mysql)
    MYSQL_PWD="$password" mysql --batch --raw --skip-column-names \
      -h "${_profile[host]}" \
      -P "${_profile[port]}" \
      -u "${_profile[user]}" \
      "${_profile[name]}" \
      -e "${_plan[sql]}" 2>"$error_file" | _apply_separators "${_plan[field_separator]}" "${_plan[line_terminator]}" >"${_plan[export_file]}"
    ;;
  postgres)
    PGPASSWORD="$password" psql \
      -h "${_profile[host]}" \
      -p "${_profile[port]}" \
      -U "${_profile[user]}" \
      -d "${_profile[name]}" \
      -c "\\copy (${_plan[sql]}) TO STDOUT WITH (FORMAT text, DELIMITER E'\\t')" 2>"$error_file" |
      _apply_separators "${_plan[field_separator]}" "${_plan[line_terminator]}" >"${_plan[export_file]}"
    ;;
  *)
    rm -f "$error_file"
    printf 'ERROR: unsupported DB type: %s\n' "${_plan[db_type]}" >&2
    return 1
    ;;
  esac

  local db_exit_code=${PIPESTATUS[0]}
  if [[ "$db_exit_code" -ne 0 ]]; then
    printf 'ERROR: %s failed for %s: %s\n' "${_plan[db_type]}" "${_profile[name]}" "$(cat "$error_file")" >&2
    rm -f "$error_file"
    return 1
  fi

  rm -f "$error_file"
}
