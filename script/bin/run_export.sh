#!/usr/bin/env bash

USE_FAKE_BIN=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

JOBS_CONFIG="$PROJECT_DIR/etc/local/jobs.properties"
ENV_CONFIG="$PROJECT_DIR/etc/env.properties"

if [[ -z "${1:-}" ]]; then
  printf 'Usage: %s YYYYMMDD\n' "$0" >&2
  exit 1
fi

PARAM_DATE="$(date +%Y%m%d)"
PARAM_FILE_NAME_SCRIPT="${0##*/}"

INPUT_DATE="$1"

if ! date -d "$INPUT_DATE" +%Y%m%d >/dev/null 2>&1; then
  printf 'ERROR: invalid date: %s\n' "$INPUT_DATE" >&2
  exit 1
fi

PARAM_CUR_DATE="$(date -d "$INPUT_DATE" +%Y-%m-%d)"

source "$ENV_CONFIG"

LOG_FILE="$ENV_LOG_FILE"

mkdir -p "$(dirname "$LOG_FILE")"

if [[ "$USE_FAKE_BIN" == true ]]; then
  FAKE_DIR="$(mktemp -d)"
  trap 'rm -rf "$FAKE_DIR"' EXIT

  cat >"$FAKE_DIR/mysql" <<'EOF'
#!/usr/bin/env bash
printf '1\tAlice\talice@example.com\tshort blog\t2026-01-01\n'
printf '2\tBob\tbob@example.com\tmedium length blog content\t2026-01-02\n'
EOF
  chmod +x "$FAKE_DIR/mysql"
  export PATH="$FAKE_DIR:$PATH"
fi

exec "$PROJECT_DIR/bin/exportctl.sh" run \
  --jobs-config "$JOBS_CONFIG" \
  --env-config "$ENV_CONFIG" \
  --date "$PARAM_CUR_DATE" \
  2>&1 | tee "$LOG_FILE"
