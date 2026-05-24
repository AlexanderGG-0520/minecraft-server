#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh

expect_failure() {
  local name="$1"
  shift

  if ( "$@" ); then
    echo "FAIL: ${name}: command unexpectedly succeeded" >&2
    exit 1
  fi
}

expect_refusal() {
  local name="$1"
  local expected="$2"
  shift 2

  local output
  output="$({ expect_failure "${name}" "$@"; } 2>&1)"
  printf '%s\n' "$output" | grep -E "^\[[^]]+\] \[ERROR\] ${expected}$" >/dev/null
}

expect_refusal "empty rm -f" "Refusing to remove unsafe path" safe_rm_f ""
expect_refusal "root rm -rf" "Refusing to remove unsafe path" safe_rm_rf /
expect_refusal "triple-slash rm -rf" "Refusing to remove unsafe path" safe_rm_rf ///
expect_refusal "dot-root rm -rf" "Refusing to remove unsafe path" safe_rm_rf /.
expect_refusal "dot-dot-root rm -rf" "Refusing to remove unsafe path" safe_rm_rf /..
expect_refusal "empty mv source" "Refusing to move from unsafe path" safe_mv "" "$tmp/dst"
expect_refusal "dot-dot-root mv source" "Refusing to move from unsafe path" safe_mv /.. "$tmp/dst"
expect_refusal "root mv destination" "Refusing to move to unsafe path" safe_mv "$tmp/src" /
expect_refusal "triple-slash mv destination" "Refusing to move to unsafe path" safe_mv "$tmp/src" ///
expect_refusal "dot-root mv destination" "Refusing to move to unsafe path" safe_mv "$tmp/src" /.
expect_refusal "dot-dot-root mv destination" "Refusing to move to unsafe path" safe_mv "$tmp/src" /..
expect_refusal "empty mv -f destination" "Refusing to move to unsafe path" safe_mv_f "$tmp/src" ""
expect_refusal "triple-slash mv -f destination" "Refusing to move to unsafe path" safe_mv_f "$tmp/src" ///
expect_refusal "dot-root mv -f destination" "Refusing to move to unsafe path" safe_mv_f "$tmp/src" /.
expect_refusal "dot-dot-root mv -f destination" "Refusing to move to unsafe path" safe_mv_f "$tmp/src" /..

printf '%s\n' file > "$tmp/file"
safe_rm_f "$tmp/file"
test ! -e "$tmp/file"

mkdir -p "$tmp/dir"
safe_rm_rf "$tmp/dir"
test ! -e "$tmp/dir"

printf '%s\n' src > "$tmp/src"
safe_mv "$tmp/src" "$tmp/dst"
test "$(cat "$tmp/dst")" = "src"

printf '%s\n' new > "$tmp/src"
safe_mv_f "$tmp/src" "$tmp/dst"
test "$(cat "$tmp/dst")" = "new"
