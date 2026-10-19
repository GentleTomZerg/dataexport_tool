#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
CTL="$ROOT_DIR/bin/exportctl.sh"
DEMO_DIR="$ROOT_DIR/etc/demo"
TMP_DIR="$REPO_ROOT/tmp"
FAKE_BIN="$TMP_DIR/fake_bin"

set -euo pipefail

# env.properties uses repository-relative output roots, so run from the root.
cd "$REPO_ROOT"

source "$ROOT_DIR/lib/config/properties.sh"
declare -A DEMO_ENV=()
load_props_from_file "$DEMO_DIR/env.properties" DEMO_ENV
KEY_FILE="$(props_get DEMO_ENV ENV_LENS_MNGT_TDSQL_PASSWORD_KEY_FILE)"
PWD_FILE="$(props_get DEMO_ENV ENV_LENS_MNGT_TDSQL_PASSWORD_FILE)"

mkdir -p "$FAKE_BIN" "$DEMO_DIR/pwd" "$TMP_DIR"
printf 'demo-key\n' >"$KEY_FILE"
# Regenerate the ciphertext when it is missing or truncated (a failed openssl
# would otherwise leave a file that every later run trusts and fails to read).
if [[ ! -s "$PWD_FILE" ]]; then
  printf 'demo-password' | openssl des3 -salt -in /dev/stdin -out "$PWD_FILE" \
    -pass file:"$KEY_FILE" -pbkdf2 -iter 100000
fi

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
  --jobs-config "$DEMO_DIR/jobs.properties" \
  --env-config "$DEMO_DIR/env.properties" \
  --date 2026-03-17

echo
echo "== plan explicit jobs + invalid selector =="
PATH="$FAKE_BIN:$PATH" bash "$CTL" plan \
  --jobs-config "$DEMO_DIR/jobs.properties" \
  --env-config "$DEMO_DIR/env.properties" \
  --date 2026-03-17 \
  users events_split invalid_split_tar missing_job

echo
echo "== run selected valid jobs =="
rm -rf "$TMP_DIR/demo_exports" "$TMP_DIR/demo_transfer" "$TMP_DIR/demo_archive"
PATH="$FAKE_BIN:$PATH" bash "$CTL" run \
  --jobs-config "$DEMO_DIR/jobs.properties" \
  --env-config "$DEMO_DIR/env.properties" \
  --date 2026-03-17 \
  users article_body daily_orders audit finance reporting_snapshot events_split

echo
echo "== generated files =="
find "$TMP_DIR" -maxdepth 2 -type f | sort
