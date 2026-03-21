#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common/log.sh"

_render_artifact_name() {
  local pattern="$1"
  local src="$2"
  local job_name="$3"
  local export_date="$4"
  local base out
  base="${src##*/}"
  out="$pattern"
  out="${out//\$\{JOB_NAME\}/$job_name}"
  out="${out//\$\{EXPORT_DATE\}/$export_date}"
  out="${out//\$\{BASENAME\}/$base}"
  printf '%s' "$out"
}

_compress_artifact() {
  local src="$1"
  local mode="$2"
  local overwrite="$3"
  local remove_original="$4"
  local out=""

  case "$mode" in
    gz) out="${src}.gz" ;;
    tar) out="${src}.tar" ;;
    tar.gz|tgz) out="${src}.${mode/tar.gz/tar.gz}" ;;
    *) return 1 ;;
  esac

  if [[ -f "$out" && "$overwrite" != "true" ]]; then
    printf 'ERROR: compressed output exists: %s\n' "$out" >&2
    return 1
  fi

  case "$mode" in
    gz) gzip -c "$src" >"$out" ;;
    tar) tar -cf "$out" -C "$(dirname "$src")" "$(basename "$src")" ;;
    tar.gz|tgz) tar -czf "$out" -C "$(dirname "$src")" "$(basename "$src")" ;;
  esac || return 1

  [[ "$remove_original" == "true" ]] && rm -f "$src"
  printf '%s' "$out"
}

_transfer_artifact() {
  local src="$1"
  local dest_dir="$2"
  local mode="$3"
  local overwrite="$4"
  local rename_pattern="$5"
  local job_name="$6"
  local export_date="$7"
  local target_name target_path

  mkdir -p "$dest_dir" || return 1
  if [[ -n "$rename_pattern" ]]; then
    target_name="$(_render_artifact_name "$rename_pattern" "$src" "$job_name" "$export_date")"
  else
    target_name="${src##*/}"
  fi
  target_path="${dest_dir%/}/$target_name"

  if [[ -f "$target_path" && "$overwrite" != "true" ]]; then
    printf 'ERROR: transfer output exists: %s\n' "$target_path" >&2
    return 1
  fi

  case "$mode" in
    move) mv -f "$src" "$target_path" ;;
    copy) cp -f "$src" "$target_path" ;;
    *) return 1 ;;
  esac || return 1

  printf '%s' "$target_path"
}

run_artifact_pipeline() {
  local plan_name="$1"
  local -n _plan="$plan_name"
  local artifact="${_plan[export_file]}"
  local before=""

  if [[ "${_plan[compress_enabled]}" == "true" ]]; then
    before="$artifact"
    log_job_info "${_plan[job_name]}" "stage=compress_start file=$before mode=${_plan[compress_mode]}"
    artifact="$(_compress_artifact "$artifact" "${_plan[compress_mode]}" "${_plan[compress_overwrite]}" "${_plan[compress_remove_original]}")" || return 1
    log_job_info "${_plan[job_name]}" "stage=compress_ok src=$before dest=$artifact mode=${_plan[compress_mode]} remove_original=${_plan[compress_remove_original]}"
  fi

  if [[ "${_plan[transfer_enabled]}" == "true" ]]; then
    before="$artifact"
    log_job_info "${_plan[job_name]}" "stage=transfer_start file=$before dir=${_plan[transfer_dir]} mode=${_plan[transfer_mode]}"
    artifact="$(_transfer_artifact "$artifact" "${_plan[transfer_dir]}" "${_plan[transfer_mode]}" "${_plan[transfer_overwrite]}" "${_plan[transfer_rename]}" "${_plan[job_name]}" "${EXPORT_DATE:-}")" || return 1
    log_job_info "${_plan[job_name]}" "stage=transfer_ok src=$before dest=$artifact mode=${_plan[transfer_mode]}"
  fi

  _plan[artifact_path]="$artifact"
}
