#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export DATA_DIR="$tmp/data"
export __SOURCED=1
export EULA=true
mkdir -p "$DATA_DIR"

source ./entrypoint.sh >/dev/null

uuid_for_player() {
  case "$1" in
    Steve) printf '%s\n' "00000000000000000000000000000001" ;;
    Alex) printf '%s\n' "00000000000000000000000000000002" ;;
    Notch) printf '%s\n' "00000000000000000000000000000003" ;;
    Jeb) printf '%s\n' "00000000000000000000000000000004" ;;
    *) return 1 ;;
  esac
}

assert_names() {
  local file="$1"
  shift

  jq -e --argjson expected "$(printf '%s\n' "$@" | jq -R . | jq -s .)" \
    'map(.name) == $expected' "$file" >/dev/null
}

OPS_USERS="Steve"
install_ops >/dev/null
assert_names "$DATA_DIR/ops.json" "Steve"

OPS_USERS="Steve, Alex"
install_ops >/dev/null
assert_names "$DATA_DIR/ops.json" "Steve" "Alex"

ENABLE_WHITELIST=true
WHITELIST_USERS="Notch"
install_whitelist >/dev/null
assert_names "$DATA_DIR/whitelist.json" "Notch"

WHITELIST_USERS="Notch, Jeb"
install_whitelist >/dev/null
assert_names "$DATA_DIR/whitelist.json" "Notch" "Jeb"

safe_rm_f "$DATA_DIR/ops.json"
safe_rm_f "$DATA_DIR/whitelist.json"

unset OPS_USERS
install_ops >/dev/null
test ! -e "$DATA_DIR/ops.json"

OPS_USERS=""
install_ops >/dev/null
test ! -e "$DATA_DIR/ops.json"

unset WHITELIST_USERS
install_whitelist >/dev/null
test ! -e "$DATA_DIR/whitelist.json"

WHITELIST_USERS=""
install_whitelist >/dev/null
test ! -e "$DATA_DIR/whitelist.json"
