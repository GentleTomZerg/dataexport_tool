#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/crypto.sh"

# Simple assertion helpers for readable test output.
assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $msg" >&2
    echo "  expected: [$expected]" >&2
    echo "  actual:   [$actual]" >&2
    exit 1
  fi
}

assert_true() {
  local cond="$1"
  local msg="$2"
  if ! eval "$cond"; then
    echo "FAIL: $msg" >&2
    exit 1
  fi
}

# Run a command in a subshell and expect it to fail.
assert_fail() {
  local msg="$1"
  shift
  if ("$@") >/dev/null 2>&1; then
    echo "FAIL: $msg" >&2
    exit 1
  fi
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

OPENSSL_LOG="$TMP_DIR/openssl.log"
OPENSSL_STDIN_FILE="$TMP_DIR/openssl.stdin"

cat > "$FAKE_BIN/openssl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

: "${OPENSSL_LOG:?}"
: "${OPENSSL_STDIN_FILE:?}"

printf '%s\n' "$*" >>"$OPENSSL_LOG"

# Capture stdin only when explicitly reading from /dev/stdin.
read_stdin=0
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-in" && "$arg" == "/dev/stdin" ]]; then
    read_stdin=1
    break
  fi
  prev="$arg"
done
if [[ "$read_stdin" -eq 1 ]]; then
  cat >"$OPENSSL_STDIN_FILE"
else
  : >"$OPENSSL_STDIN_FILE"
fi

# If -out is provided, write a placeholder to that file.
out_file=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-out" ]]; then
    out_file="$arg"
    break
  fi
  prev="$arg"
 done
if [[ -n "$out_file" ]]; then
  printf 'ENC' >"$out_file"
fi

# Print output if requested.
if [[ -n "${OPENSSL_OUTPUT:-}" ]]; then
  printf '%s' "$OPENSSL_OUTPUT"
fi
FAKE
chmod +x "$FAKE_BIN/openssl"

export PATH="$FAKE_BIN:$PATH"
export OPENSSL_LOG OPENSSL_STDIN_FILE

PWD_FILE="$TMP_DIR/secret.pwd"
KEY_FILE="$TMP_DIR/keyfile.txt"
printf 'dummy' >"$PWD_FILE"
printf 'key' >"$KEY_FILE"

# decrypt_password: success path with correct openssl args.
DB_PASSWORD_KEY_FILE="$KEY_FILE"
export DB_PASSWORD_KEY_FILE
OPENSSL_OUTPUT="plain"
export OPENSSL_OUTPUT

result="$(decrypt_password "$PWD_FILE")"
assert_eq "plain" "$result" "decrypt output"
assert_true "grep -q -- 'des3 -d -salt -in $PWD_FILE -pass file:$KEY_FILE -pbkdf2 -iter 100000' '$OPENSSL_LOG'" "decrypt args"

# decrypt_password: missing key file should fail.
DB_PASSWORD_KEY_FILE="$TMP_DIR/missing.key"
export DB_PASSWORD_KEY_FILE
assert_fail "decrypt should fail when key file missing" decrypt_password "$PWD_FILE"

# encode_password: writes output file and uses expected args.
DB_PASSWORD_KEY_FILE="$KEY_FILE"
export DB_PASSWORD_KEY_FILE
OPENSSL_OUTPUT=""
export OPENSSL_OUTPUT

OUT_FILE="$TMP_DIR/out/secret.pwd"
encode_password "mypassword" "$OUT_FILE"
assert_true "[[ -f '$OUT_FILE' ]]" "encode output file exists"
assert_eq "ENC" "$(cat "$OUT_FILE")" "encode output contents"
assert_eq "mypassword" "$(cat "$OPENSSL_STDIN_FILE")" "encode stdin"
assert_true "grep -q -- 'des3 -salt -in /dev/stdin -out $OUT_FILE -pass file:$KEY_FILE -pbkdf2 -iter 100000' '$OPENSSL_LOG'" "encode args"

echo "OK: crypto_test.sh"
