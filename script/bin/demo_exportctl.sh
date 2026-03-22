#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$ROOT_DIR/bin/exportctl.sh"
DEMO_DIR="$ROOT_DIR/etc/demo"
TMP_DIR="$ROOT_DIR/tmp"
FAKE_BIN="$TMP_DIR/fake_bin"
KEY_FILE="$DEMO_DIR/pwd/key_file"

set -euo pipefail

mkdir -p "$FAKE_BIN" "$DEMO_DIR/pwd" "$TMP_DIR"
printf 'demo-key\n' >"$KEY_FILE"

cat >"$FAKE_BIN/mysql" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '1\tAlice\talice@example.com\n2\tBob\tbob@example.com\n'
EOF

cat >"$FAKE_BIN/psql" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '101\tmetric_a\t99\n102\tmetric_b\t100\n'
EOF

chmod +x "$FAKE_BIN/mysql" "$FAKE_BIN/psql"

echo "== validate all jobs =="
PATH="$FAKE_BIN:$PATH" bash "$CTL" validate \
  --db-config "$DEMO_DIR/db.properties" \
  --jobs-config "$DEMO_DIR/jobs.properties" \
  --env-config "$DEMO_DIR/env.properties" \
  --date 2026-03-17

echo
echo "== plan explicit jobs + invalid selector =="
PATH="$FAKE_BIN:$PATH" bash "$CTL" plan \
  --db-config "$DEMO_DIR/db.properties" \
  --jobs-config "$DEMO_DIR/jobs.properties" \
  --env-config "$DEMO_DIR/env.properties" \
  --date 2026-03-17 \
  users article_body invalid_unknown_profile missing_job

echo
echo "== run selected valid jobs =="
rm -rf "$ROOT_DIR/tmp/demo_exports" "$ROOT_DIR/tmp/demo_transfer" "$ROOT_DIR/tmp/demo_archive"
PATH="$FAKE_BIN:$PATH" bash "$CTL" run \
  --db-config "$DEMO_DIR/db.properties" \
  --jobs-config "$DEMO_DIR/jobs.properties" \
  --env-config "$DEMO_DIR/env.properties" \
  --date 2026-03-17 \
  users article_body daily_orders audit finance reporting_snapshot

echo
echo "== generated files =="
find "$ROOT_DIR/tmp" -maxdepth 2 -type f | sort
