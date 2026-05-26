#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

calls_file="$tmp/calls"
: > "$calls_file"

record_call() {
  if [[ -s "$calls_file" ]]; then
    printf ' %s' "$1" >> "$calls_file"
  else
    printf '%s' "$1" > "$calls_file"
  fi
}

install() {
  record_call install
}

runtime() {
  record_call runtime
}

log() {
  record_call "log:$1:$2"
}

is_true() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

source ./scripts/lib/runtime_phase.sh

INSTALL_ONLY=false
run_runtime_phase
calls="$(cat "$calls_file")"
if [[ "$calls" != "install runtime" ]]; then
  echo "FAIL: expected normal runtime phase to call install then runtime" >&2
  printf 'actual: %s\n' "$calls" >&2
  exit 1
fi

: > "$calls_file"
INSTALL_ONLY=true
set +e
(
  run_runtime_phase
) >/dev/null 2>&1
status=$?
set -e

if [[ "$status" -ne 0 ]]; then
  echo "FAIL: expected install-only runtime phase to exit 0" >&2
  exit 1
fi

output="$(cat "$calls_file")"
expected="install log:WARN:INSTALL_ONLY=true, skipping runtime launch and exiting"
if [[ "$output" != "$expected" ]]; then
  echo "FAIL: expected install-only runtime phase to install, log, and skip runtime" >&2
  printf 'expected: %s\nactual:   %s\n' "$expected" "$output" >&2
  exit 1
fi
