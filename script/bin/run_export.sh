#!/usr/bin/env bash

USE_FAKE_BIN=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DB_CONFIG="$PROJECT_DIR/etc/local/db.properties"
JOBS_CONFIG="$PROJECT_DIR/etc/local/jobs.properties"
ENV_CONFIG="$PROJECT_DIR/etc/env.properties"

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
  --db-config "$DB_CONFIG" \
  --jobs-config "$JOBS_CONFIG" \
  --env-config "$ENV_CONFIG" \
  --date "$1"
