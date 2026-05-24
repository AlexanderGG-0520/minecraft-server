#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh

expect_refusal() {
  local expected="$1"
  shift

  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  test "$status" -eq 1
  printf '%s\n' "$output" | grep -E "^\[[^]]+\] \[ERROR\] ${expected}$" >/dev/null
}

expect_refusal "Refusing to remove unsafe path" safe_rm_f ""
expect_refusal "Refusing to remove unsafe path" safe_rm_rf /
expect_refusal "Refusing to remove unsafe path" safe_rm_rf ///
expect_refusal "Refusing to remove unsafe path" safe_rm_rf /.
expect_refusal "Refusing to remove unsafe path" safe_rm_rf /..
expect_refusal "Refusing to move from unsafe path" safe_mv "" "$tmp/dst"
expect_refusal "Refusing to move from unsafe path" safe_mv /.. "$tmp/dst"
expect_refusal "Refusing to move to unsafe path" safe_mv "$tmp/src" /
expect_refusal "Refusing to move to unsafe path" safe_mv "$tmp/src" ///
expect_refusal "Refusing to move to unsafe path" safe_mv "$tmp/src" /.
expect_refusal "Refusing to move to unsafe path" safe_mv "$tmp/src" /..
expect_refusal "Refusing to move to unsafe path" safe_mv_f "$tmp/src" ""
expect_refusal "Refusing to move to unsafe path" safe_mv_f "$tmp/src" ///
expect_refusal "Refusing to move to unsafe path" safe_mv_f "$tmp/src" /.
expect_refusal "Refusing to move to unsafe path" safe_mv_f "$tmp/src" /..

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
