#!/usr/bin/env bash

declare CLI_CMD=""
declare CLI_SUBCMD=""
declare CLI_DB_CONFIG=""
declare CLI_JOBS_CONFIG=""
declare CLI_ENV_CONFIG=""
declare CLI_DATE=""
declare CLI_DB_PROFILE=""
declare CLI_PASSWORD=""
declare CLI_KEY_FILE=""
declare CLI_PASSWORD_FILE=""
declare -ag CLI_SELECTORS=()

_args_require_value() {
  [[ $# -ge 2 && -n "${2:-}" && "${2:0:1}" != "-" ]]
}

_args_validate_date() {
  [[ -z "$1" || "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

parse_exportctl_args() {
  CLI_CMD="${1:-}"
  [[ -n "$CLI_CMD" ]] || return 1
  shift || true

  CLI_SELECTORS=()

  case "$CLI_CMD" in
    validate|plan|run)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --db-config)
            _args_require_value "$@" || return 1
            CLI_DB_CONFIG="$2"
            shift 2
            ;;
          --jobs-config)
            _args_require_value "$@" || return 1
            CLI_JOBS_CONFIG="$2"
            shift 2
            ;;
          --env-config)
            _args_require_value "$@" || return 1
            CLI_ENV_CONFIG="$2"
            shift 2
            ;;
          --date)
            _args_require_value "$@" || return 1
            CLI_DATE="$2"
            shift 2
            ;;
          -h|--help)
            return 1
            ;;
          *)
            CLI_SELECTORS+=("$1")
            shift
            ;;
        esac
      done
      [[ -n "$CLI_DB_CONFIG" && -n "$CLI_JOBS_CONFIG" ]] || return 1
      _args_validate_date "$CLI_DATE" || return 1
      ;;
    password)
      CLI_SUBCMD="${1:-}"
      [[ "$CLI_SUBCMD" == "encode" || "$CLI_SUBCMD" == "decode" ]] || return 1
      shift || true
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --db-config)
            _args_require_value "$@" || return 1
            CLI_DB_CONFIG="$2"
            shift 2
            ;;
          --db-profile)
            _args_require_value "$@" || return 1
            CLI_DB_PROFILE="$2"
            shift 2
            ;;
          --password)
            _args_require_value "$@" || return 1
            CLI_PASSWORD="$2"
            shift 2
            ;;
          --password-file)
            _args_require_value "$@" || return 1
            CLI_PASSWORD_FILE="$2"
            shift 2
            ;;
          --key-file)
            _args_require_value "$@" || return 1
            CLI_KEY_FILE="$2"
            shift 2
            ;;
          *)
            return 1
            ;;
        esac
      done
      if [[ "$CLI_SUBCMD" == "encode" ]]; then
        [[ -n "$CLI_DB_CONFIG" && -n "$CLI_DB_PROFILE" && -n "$CLI_PASSWORD" && -n "$CLI_KEY_FILE" ]] || return 1
      else
        [[ -n "$CLI_PASSWORD_FILE" && -n "$CLI_KEY_FILE" ]] || return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}
