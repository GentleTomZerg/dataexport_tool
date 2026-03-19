#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "This library requires bash." >&2
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

_post_export_ext() {
  local name="$1"
  if [[ "$name" == *.* ]]; then
    printf '.%s' "${name##*.}"
  else
    printf ''
  fi
}

_post_export_basename() {
  local name="$1"
  printf '%s' "${name##*/}"
}

_post_export_noext() {
  local name="$1"
  local base
  base="$(_post_export_basename "$name")"
  printf '%s' "${base%.*}"
}

_post_export_render_name() {
  local pattern="$1"
  local src="$2"
  local base ext
  base="$(_post_export_basename "$src")"
  ext="$(_post_export_ext "$base")"

  local out="$pattern"
  out="${out//\$\{JOB_NAME\}/$JOB_NAME}"
  out="${out//\$\{EXPORT_DATE\}/$EXPORT_DATE}"
  out="${out//\$\{BASENAME\}/$base}"
  out="${out//\$\{EXT\}/$ext}"
  printf '%s' "$out"
}

_post_export_require_file() {
  local path="$1"
  if [[ -z "$path" || ! -f "$path" ]]; then
    echo "File not found: $path" >&2
    return 1
  fi
}

compress_file() {
  local src="$1"
  local mode="$2"
  local overwrite="$3"
  local remove_original="$4"
  local out=""

  _post_export_require_file "$src"

  case "$mode" in
    gz)
      out="${src}.gz"
      ;;
    tar)
      out="${src}.tar"
      ;;
    tar.gz|tgz)
      out="${src}.tar.gz"
      [[ "$mode" == "tgz" ]] && out="${src}.tgz"
      ;;
    *)
      echo "Unsupported compress mode: $mode" >&2
      return 1
      ;;
  esac

  if [[ -f "$out" && "$overwrite" != "true" ]]; then
    echo "Compressed file exists and overwrite=false: $out" >&2
    return 1
  fi

  case "$mode" in
    gz)
      gzip -c "$src" >"$out"
      ;;
    tar)
      tar -cf "$out" -C "$(dirname "$src")" "$(basename "$src")"
      ;;
    tar.gz|tgz)
      tar -czf "$out" -C "$(dirname "$src")" "$(basename "$src")"
      ;;
  esac

  if [[ "$remove_original" == "true" ]]; then
    rm -f "$src"
  fi

  printf '%s' "$out"
}

transfer_file() {
  local src="$1"
  local dest_dir="$2"
  local mode="$3"
  local overwrite="$4"
  local rename_pattern="$5"
  local target_name target_path

  _post_export_require_file "$src"

  if [[ -z "$dest_dir" ]]; then
    echo "Missing transfer destination directory" >&2
    return 1
  fi

  mkdir -p "$dest_dir"

  if [[ -n "$rename_pattern" ]]; then
    target_name="$(_post_export_render_name "$rename_pattern" "$src")"
  else
    target_name="$(_post_export_basename "$src")"
  fi
  target_path="${dest_dir%/}/$target_name"

  if [[ -f "$target_path" && "$overwrite" != "true" ]]; then
    echo "Transfer target exists and overwrite=false: $target_path" >&2
    return 1
  fi

  case "$mode" in
    move)
      mv -f "$src" "$target_path"
      ;;
    copy)
      cp -f "$src" "$target_path"
      ;;
    *)
      echo "Unsupported transfer mode: $mode" >&2
      return 1
      ;;
  esac

  printf '%s' "$target_path"
}
