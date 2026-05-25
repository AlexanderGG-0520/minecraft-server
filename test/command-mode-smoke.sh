#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

log_file="$tmp/log"

log() {
  printf '%s:%s\n' "$1" "$2" >> "$log_file"
}

rcon_exec() {
  printf '%s\n' "$*" > "$tmp/rcon-exec-args"
  return 7
}

rcon_say() {
  printf '%s\n' "$*" > "$tmp/rcon-say-args"
  return 8
}

rcon_stop_once() {
  printf '%s\n' called > "$tmp/rcon-stop-called"
  return "${RCON_STOP_STATUS:-0}"
}

source ./scripts/lib/command_mode.sh

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: ${label}: expected '${expected}', got '${actual}'" >&2
    exit 1
  fi
}

run_mode_consumes_run_arg() {
  INSTALL_ONLY=false
  set -- run extra
  handle_command_mode "$@"
  shift "${COMMAND_MODE_SHIFT}" || true

  assert_eq false "$INSTALL_ONLY" "run leaves INSTALL_ONLY false"
  assert_eq 1 "$#" "run leaves remaining args"
  assert_eq extra "$1" "run shifts one arg"
}

run_mode_defaults_to_run_without_args() {
  INSTALL_ONLY=false
  set --
  handle_command_mode "$@"
  shift "${COMMAND_MODE_SHIFT}" || true

  assert_eq false "$INSTALL_ONLY" "default run leaves INSTALL_ONLY false"
  assert_eq 0 "$#" "default run keeps empty args empty"
}

install_only_sets_flag_and_consumes_arg() {
  INSTALL_ONLY=false
  set -- install-only leftover
  handle_command_mode "$@"
  shift "${COMMAND_MODE_SHIFT}" || true

  assert_eq true "$INSTALL_ONLY" "install-only sets INSTALL_ONLY"
  assert_eq 1 "$#" "install-only leaves remaining args"
  assert_eq leftover "$1" "install-only shifts one arg"
}

unknown_mode_is_unchanged() {
  INSTALL_ONLY=false
  set -- unknown value
  handle_command_mode "$@"
  shift "${COMMAND_MODE_SHIFT}" || true

  assert_eq false "$INSTALL_ONLY" "unknown leaves INSTALL_ONLY false"
  assert_eq 2 "$#" "unknown leaves args unchanged"
  assert_eq unknown "$1" "unknown first arg preserved"
}

rcon_mode_exits_with_rcon_exec_status() {
  set +e
  ( handle_command_mode rcon list players )
  local status=$?
  set -e

  assert_eq 7 "$status" "rcon exits with rcon_exec status"
  assert_eq "list players" "$(cat "$tmp/rcon-exec-args")" "rcon forwards args"
}

rcon_say_mode_exits_with_rcon_say_status() {
  set +e
  ( handle_command_mode rcon-say hello world )
  local status=$?
  set -e

  assert_eq 8 "$status" "rcon-say exits with rcon_say status"
  assert_eq "hello world" "$(cat "$tmp/rcon-say-args")" "rcon-say forwards args"
}

rcon_stop_mode_exits_zero_on_success() {
  RCON_STOP_STATUS=0
  set +e
  ( handle_command_mode rcon-stop )
  local status=$?
  set -e

  assert_eq 0 "$status" "rcon-stop exits zero on success"
  assert_eq called "$(cat "$tmp/rcon-stop-called")" "rcon-stop calls helper"
}

rcon_stop_mode_exits_zero_on_failure() {
  RCON_STOP_STATUS=9
  : > "$log_file"

  set +e
  ( handle_command_mode rcon-stop )
  local status=$?
  set -e

  assert_eq 0 "$status" "rcon-stop exits zero on failure"
  assert_eq "WARN:[shutdown] rcon-stop command failed; exiting 0 for Kubernetes preStop compatibility" "$(cat "$log_file")" "rcon-stop warning"
}

run_mode_consumes_run_arg
run_mode_defaults_to_run_without_args
install_only_sets_flag_and_consumes_arg
unknown_mode_is_unchanged
rcon_mode_exits_with_rcon_exec_status
rcon_say_mode_exits_with_rcon_say_status
rcon_stop_mode_exits_zero_on_success
rcon_stop_mode_exits_zero_on_failure
