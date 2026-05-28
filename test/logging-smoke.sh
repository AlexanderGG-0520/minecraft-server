#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

source ./scripts/lib/logging.sh

expect_die() {
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

expect_die "single message" die "single message"
expect_die "foo bar baz" die foo bar baz

