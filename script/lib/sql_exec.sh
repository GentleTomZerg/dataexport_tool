#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This library requires bash." >&2
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

## Execute SQL and export results to file using the selected DB_TYPE.
## Default DB_TYPE is mysql (can be set in DB profile config).
## Supports: mysql, postgres
## If a password file exists, it will be decrypted using DB_PASSWORD_KEY_FILE.
## Usage: sql_exec_export "$sql" "/path/to/output.tsv" ["\\t"] ["\\n"]
_sql_exec_password_from_file() {
  local pwd_file="$1"
  if [[ -n "$pwd_file" && -f "$pwd_file" ]]; then
    if declare -F decrypt_password >/dev/null 2>&1; then
      decrypt_password "$pwd_file"
      return 0
    fi
    echo "decrypt_password is not available; source lib/crypto.sh before using password files." >&2
    return 1
  fi
  return 0
}

## Apply raw separators (e.g. "\t", "\n", "\r") to mysql/psql tab output.
## This keeps the DB client output in TSV, then rewrites to the requested format.
_sql_exec_apply_separators() {
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

_sql_exec_with_mysql() {
  local sql="$1"
  local out_file="$2"
  local field_sep_raw="$3"
  local line_term_raw="$4"
  local db_password="$5"

  if [[ -n "$db_password" ]]; then
    MYSQL_PWD="$db_password" \
      mysql --batch --raw --skip-column-names \
      -h "$DB_HOST" \
      -P "$DB_PORT" \
      -u "$DB_USER" \
      "$DB_NAME" \
      -e "$sql" | _sql_exec_apply_separators "$field_sep_raw" "$line_term_raw" >"$out_file"
  else
    mysql --batch --raw --skip-column-names \
      -h "$DB_HOST" \
      -P "$DB_PORT" \
      -u "$DB_USER" \
      "$DB_NAME" \
      -e "$sql" | _sql_exec_apply_separators "$field_sep_raw" "$line_term_raw" >"$out_file"
  fi
}

_sql_exec_with_postgres() {
  local sql="$1"
  local out_file="$2"
  local field_sep_raw="$3"
  local line_term_raw="$4"
  local db_password="$5"

  if [[ -n "$db_password" ]]; then
    PGPASSWORD="$db_password" psql \
      -h "$DB_HOST" \
      -p "$DB_PORT" \
      -U "$DB_USER" \
      -d "$DB_NAME" \
      -c "\\copy (${sql}) TO STDOUT WITH (FORMAT text, DELIMITER E'\\t')" | \
      _sql_exec_apply_separators "$field_sep_raw" "$line_term_raw" >"$out_file"
  else
    psql \
      -h "$DB_HOST" \
      -p "$DB_PORT" \
      -U "$DB_USER" \
      -d "$DB_NAME" \
      -c "\\copy (${sql}) TO STDOUT WITH (FORMAT text, DELIMITER E'\\t')" | \
      _sql_exec_apply_separators "$field_sep_raw" "$line_term_raw" >"$out_file"
  fi
}

sql_exec_export() {
  local sql="$1"
  local out_file="$2"
  local db_type="${DB_TYPE:-mysql}"
  local field_sep_raw="${3:-${JOB_FIELD_SEPARATOR:-\\t}}"
  local line_term_raw="${4:-${JOB_LINE_TERMINATOR:-\\n}}"
  local pwd_file db_password=""

  if [[ -z "$out_file" ]]; then
    echo "Missing export output file path" >&2
    return 1
  fi

  pwd_file="${DB_PASSWORD_FILE:-}"
  if [[ -z "$pwd_file" ]] && declare -F db_password_file >/dev/null 2>&1; then
    pwd_file="$(db_password_file)"
  fi
  db_password="$(_sql_exec_password_from_file "$pwd_file")"

  case "$db_type" in
    mysql)
      _sql_exec_with_mysql "$sql" "$out_file" "$field_sep_raw" "$line_term_raw" "$db_password"
      ;;
    postgres)
      _sql_exec_with_postgres "$sql" "$out_file" "$field_sep_raw" "$line_term_raw" "$db_password"
      ;;
    *)
      echo "Unsupported DB_TYPE: $db_type" >&2
      return 1
      ;;
  esac
}
