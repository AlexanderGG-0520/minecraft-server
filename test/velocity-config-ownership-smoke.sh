#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh
source ./scripts/lib/velocity_config.sh

normalize_toml_key() {
  local key="$1"
  key="${key//-/_}"
  key="${key// /_}"
  printf '%s' "${key}"
}

trim_ws() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

expect_failure() {
  local expected="$1"
  shift

  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  test "$status" -ne 0
  printf '%s\n' "$output" | grep -F "$expected" >/dev/null
}

snapshot_file_state() {
  local file="$1"

  stat -c '%a %u:%g' "$file"
}

TYPE=velocity

DATA_DIR="$tmp/user-managed"
mkdir -p "$DATA_DIR"
printf '%s\n' "user velocity config" > "$DATA_DIR/velocity.toml"
printf '%s\n' "user-secret" > "$DATA_DIR/forwarding.secret"
chmod 0444 "$DATA_DIR/velocity.toml" "$DATA_DIR/forwarding.secret"
toml_state="$(snapshot_file_state "$DATA_DIR/velocity.toml")"
secret_state="$(snapshot_file_state "$DATA_DIR/forwarding.secret")"

unset VELOCITY_SERVERS VELOCITY_SECRET
generate_velocity_toml
test "$(cat "$DATA_DIR/velocity.toml")" = "user velocity config"
test "$(cat "$DATA_DIR/forwarding.secret")" = "user-secret"
test "$(snapshot_file_state "$DATA_DIR/velocity.toml")" = "$toml_state"
test "$(snapshot_file_state "$DATA_DIR/forwarding.secret")" = "$secret_state"

DATA_DIR="$tmp/generated"
mkdir -p "$DATA_DIR"
VELOCITY_SERVERS="lobby=127.0.0.1:25565"
VELOCITY_SECRET="generated-secret"
generate_velocity_toml
test -f "$DATA_DIR/velocity.toml"
grep -F 'forwarding-secret = "generated-secret"' "$DATA_DIR/velocity.toml" >/dev/null
grep -F '  lobby = "127.0.0.1:25565"' "$DATA_DIR/velocity.toml" >/dev/null
test ! -e "$DATA_DIR/forwarding.secret"
test ! -e "$DATA_DIR"/.velocity.toml.tmp.*
test "$(stat -c '%a' "$DATA_DIR/velocity.toml")" = "644"

DATA_DIR="$tmp/not-writable"
mkdir -p "$DATA_DIR"
chmod 0555 "$DATA_DIR"
expect_failure "Failed to generate velocity.toml fallback: $DATA_DIR is not writable" generate_velocity_toml
test ! -e "$DATA_DIR/velocity.toml"
test ! -e "$DATA_DIR"/.velocity.toml.tmp.*

