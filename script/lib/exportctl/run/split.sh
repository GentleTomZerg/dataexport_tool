#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/artifact.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../model" && pwd)/job.sh"

# File split (Pass 2): split an uncompressed draft export file on line boundaries
# and gzip each part to its own artifact.
#
# The limit is measured on the compressed gz bytes, so the uncompressed budget
# is a guess that is recalibrated after every part from the measured ratio:
#   budget = MAX_SIZE * (part_csv_bytes / part_gz_bytes) * 0.95
# A part whose gz still exceeds MAX_SIZE is split again with the measured ratio
# (rare); a single line is always emitted on its own even if it overflows.

_file_size() {
  wc -c <"$1" | tr -d '[:space:]'
}

# Calibrated uncompressed budget for the next part, from a measured part.
_calibrate_budget() {
  local max_bytes="$1"
  local part_csv_bytes="$2"
  local part_gz_bytes="$3"

  LC_ALL=C awk -v m="$max_bytes" -v c="$part_csv_bytes" -v g="$part_gz_bytes" '
    BEGIN {
      if (g <= 0) g = 1
      value = int(m * c / g * 0.95)
      if (value < 1) value = 1
      printf "%d", value
    }
  '
}

# Pick the longest run of whole lines starting at $offset whose uncompressed
# bytes fit in $budget, always taking at least one line. Prints "<lines> <bytes>".
_next_part_span() {
  local file="$1"
  local offset="$2"
  local budget="$3"
  local total="$4"
  local remaining=$((total - offset))

  (
    # tail gets SIGPIPE once awk stops early; that is expected, not an error.
    set +o pipefail
    tail -c "+$((offset + 1))" "$file" |
      LC_ALL=C awk -v budget="$budget" -v remaining="$remaining" '
        {
          len = length($0) + 1
          if (n > 0 && acc + len > budget) {
            done = 1
            printf "%d %d\n", n, acc
            exit
          }
          acc += len
          n++
        }
        END {
          if (done) exit
          if (acc > remaining) acc = remaining
          printf "%d %d\n", n, acc
        }
      '
  )
}

# Copy an exact byte range of $file to stdout, preserving the original bytes.
_copy_part_span() {
  local file="$1"
  local offset="$2"
  local bytes="$3"

  (
    # tail gets SIGPIPE once head has all its bytes; expected, not an error.
    set +o pipefail
    tail -c "+$((offset + 1))" "$file" | head -c "$bytes"
  )
}

# Gzip $csv_file to the part name rendered for $index. Prints the gz path.
_write_gz_part() {
  local csv_file="$1"
  local index="$2"
  local config_name="$3"
  local -n _cfg="$config_name"
  local gz_path

  gz_path="$(
    render_export_part_name "${_cfg[template]}" "$index" "${_cfg[index_width]}" \
      "${_cfg[job_name]}" "${_cfg[export_date]}"
  )" || return 1
  mkdir -p "$(dirname "$gz_path")" || return 1
  gzip -c "$csv_file" >"$gz_path" || {
    rm -f "$gz_path"
    return 1
  }
  printf '%s' "$gz_path"
}

# Calibrate the next budget from the most recently emitted part, if any.
_budget_from_last_part() {
  local parts_name="$1"
  local max_bytes="$2"
  local -n _parts="$parts_name"
  local count="${#_parts[@]}"
  local record bytes_csv bytes_gz

  ((count > 0)) || return 1
  record="${_parts[$((count - 1))]}"
  IFS='|' read -r _ _ bytes_csv bytes_gz _ <<<"$record"
  _calibrate_budget "$max_bytes" "$bytes_csv" "$bytes_gz"
}

# Split $file into parts, appending "<index>|<lines>|<bytes_csv>|<bytes_gz>|<gz_path>"
# records to the array named by $parts_name and advancing the counter named by
# $index_name. Re-splits an oversized part against the temporary file it came from.
# $config_name names an associative array with max_bytes, index_width, template,
# job_name, export_date and tmp_dir.
_split_file_into_parts() {
  local file="$1"
  local budget="$2"
  local parts_name="$3"
  local index_name="$4"
  local config_name="$5"
  local -n _parts="$parts_name"
  local -n _index="$index_name"
  local -n _cfg="$config_name"

  local max_bytes="${_cfg[max_bytes]}"
  local tmp_dir="${_cfg[tmp_dir]}"
  local total offset part_csv_file part_lines part_csv_bytes gz_path gz_bytes new_budget
  total="$(_file_size "$file")"
  offset=0

  while ((offset < total)); do
    part_csv_file="$(mktemp "$tmp_dir/part.XXXXXX")" || return 1

    if ! read -r part_lines part_csv_bytes < <(_next_part_span "$file" "$offset" "$budget" "$total"); then
      rm -f "$part_csv_file"
      printf 'ERROR: FILE_SPLIT could not split %s\n' "$file" >&2
      return 1
    fi
    if [[ ! "$part_lines" =~ ^[0-9]+$ || "$part_lines" -le 0 ]] \
      || [[ ! "$part_csv_bytes" =~ ^[0-9]+$ || "$part_csv_bytes" -le 0 ]]; then
      rm -f "$part_csv_file"
      printf 'ERROR: FILE_SPLIT produced an empty part for %s at offset %s\n' "$file" "$offset" >&2
      return 1
    fi

    _copy_part_span "$file" "$offset" "$part_csv_bytes" >"$part_csv_file" || {
      rm -f "$part_csv_file"
      return 1
    }

    gz_path="$(_write_gz_part "$part_csv_file" "$_index" "$config_name")" || {
      rm -f "$part_csv_file"
      return 1
    }
    gz_bytes="$(_file_size "$gz_path")"

    if ((gz_bytes <= max_bytes)) || ((part_lines == 1)); then
      _parts+=("${_index}|${part_lines}|${part_csv_bytes}|${gz_bytes}|${gz_path}")
      _index=$((_index + 1))
      budget="$(_calibrate_budget "$max_bytes" "$part_csv_bytes" "$gz_bytes")"
      offset=$((offset + part_csv_bytes))
      rm -f "$part_csv_file"
    else
      # The guess was too generous: drop this part and split it again with the
      # measured ratio. The clamp keeps the budget below the part size, so the
      # recursion always makes progress. A single line never reaches this branch.
      rm -f "$gz_path"
      new_budget="$(_calibrate_budget "$max_bytes" "$part_csv_bytes" "$gz_bytes")"
      if ((new_budget >= part_csv_bytes)); then
        new_budget=$((part_csv_bytes - 1))
      fi
      ((new_budget >= 1)) || new_budget=1

      _split_file_into_parts "$part_csv_file" "$new_budget" "$parts_name" "$index_name" "$config_name" || {
        rm -f "$part_csv_file"
        return 1
      }
      budget="$(_budget_from_last_part "$parts_name" "$max_bytes")" || budget="$new_budget"
      offset=$((offset + part_csv_bytes))
      rm -f "$part_csv_file"
    fi
  done
}

# Emit one empty part (keeps the "successful job has at least a 00 part" invariant).
_emit_empty_part() {
  local config_name="$1"
  local parts_name="$2"
  local -n _cfg="$config_name"
  local -n _parts="$parts_name"
  local empty_csv="${_cfg[tmp_dir]}/empty.csv"
  local gz_path gz_bytes

  : >"$empty_csv"
  gz_path="$(_write_gz_part "$empty_csv" 0 "$config_name")" || return 1
  gz_bytes="$(_file_size "$gz_path")"
  _parts+=("0|0|0|${gz_bytes}|${gz_path}")
}

# Split <csv_path> on line boundaries, gzip each part and record the results in
# the plan as `parts` (newline-separated `index|lines|bytes_csv|bytes_gz|gz_path`)
# and `part_count`. Each gz part is <= MAX_SIZE, except when a single line is
# itself larger than MAX_SIZE.
split_and_compress_parts() {
  local csv_path="$1"
  local plan_name="$2"
  local -n _plan="$plan_name"

  if [[ ! -f "$csv_path" ]]; then
    printf 'ERROR: FILE_SPLIT input not found: %s\n' "$csv_path" >&2
    return 1
  fi

  local max_bytes index_width template job_name export_date
  if ! max_bytes="$(parse_size_to_bytes "${_plan[file_split_max_size]:-}")" || ((max_bytes <= 0)); then
    printf 'ERROR: job %s FILE_SPLIT.MAX_SIZE is invalid: %s\n' \
      "${_plan[job_name]:-}" "${_plan[file_split_max_size]:-}" >&2
    return 1
  fi
  index_width="${_plan[file_split_index_width]:-2}"
  template="${_plan[export_file]:-}"
  job_name="${_plan[job_name]:-}"
  export_date="${EXPORT_DATE:-}"

  if [[ -z "$template" ]]; then
    printf 'ERROR: job %s FILE_SPLIT needs an EXPORT_FILE template\n' "$job_name" >&2
    return 1
  fi

  local records
  records="$(
    tmp_dir="$(mktemp -d "$(dirname "$csv_path")/.file-split-parts.XXXXXX")" || exit 1
    trap 'rm -rf "$tmp_dir"' EXIT

    declare -A cfg=(
      [max_bytes]="$max_bytes"
      [index_width]="$index_width"
      [template]="$template"
      [job_name]="$job_name"
      [export_date]="$export_date"
      [tmp_dir]="$tmp_dir"
    )
    parts=()
    index=0

    if [[ "$(_file_size "$csv_path")" -eq 0 ]]; then
      _emit_empty_part cfg parts || exit 1
    else
      _split_file_into_parts "$csv_path" "$((max_bytes * 3))" parts index cfg || exit 1
    fi

    local rec
    for rec in "${parts[@]}"; do
      printf '%s\n' "$rec"
    done
  )" || return 1

  _plan[parts]="$records"
  if [[ -z "$records" ]]; then
    _plan[part_count]="0"
  else
    _plan[part_count]="$(printf '%s\n' "$records" | wc -l | tr -d '[:space:]')"
  fi
}
