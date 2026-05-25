#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh
source ./scripts/lib/runtime.sh
DATA_DIR="$tmp"

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

assert_no_marker_temp_files() {
  if find "$tmp" -maxdepth 1 -name '.server-install.json.tmp.*' -print -quit | grep -q .; then
    echo "FAIL: marker temp file was left behind" >&2
    exit 1
  fi
}

test "$(server_install_marker)" = "$tmp/.server-install.json"

write_server_install_marker "server.jar" "paper" "1.21.8" "123"
test "$(read_server_install_marker_field "$tmp/.server-install.json" artifact)" = "server.jar"
test "$(read_server_install_marker_field "$tmp/.server-install.json" type)" = "paper"
test "$(read_server_install_marker_field "$tmp/.server-install.json" version)" = "1.21.8"
test "$(read_server_install_marker_field "$tmp/.server-install.json" build)" = "123"
assert_no_marker_temp_files
assert_server_install_matches "server.jar" "paper" "1.21.8"

write_server_install_marker "server.jar" "vanilla" "1.21.8"
test "$(read_server_install_marker_field "$tmp/.server-install.json" build)" = ""
assert_no_marker_temp_files

write_server_install_marker "server.jar" "paper" "1.21.8" "123"
expect_failure \
  "server.jar was installed as TYPE=paper VERSION=1.21.8; requested TYPE=vanilla VERSION=1.21.8" \
  assert_server_install_matches "server.jar" "vanilla" "1.21.8"

rm -f "$tmp/.server-install.json"
assert_server_install_matches "server.jar" "paper" "1.21.8"

printf '{\n' > "$tmp/.server-install.json"
expect_failure "Invalid server install marker JSON: $tmp/.server-install.json" \
  assert_server_install_matches "server.jar" "paper" "1.21.8"

printf '{"artifact":"server.jar","type":"paper","version":"1.21.8"}\n' > "$tmp/.server-install.json"
expect_failure "Incomplete server install marker: $tmp/.server-install.json missing build" \
  assert_server_install_matches "server.jar" "paper" "1.21.8"

write_server_install_marker "server.jar" "paper" "1.21.8" "123"
touch "$tmp/server.jar"
TYPE=auto
resolve_type_auto
test "$TYPE" = "paper"

write_server_install_marker "server.jar" "spigot" "1.21.8" ""
touch "$tmp/server.jar"
TYPE=auto
resolve_type_auto
test "$TYPE" = "spigot"

printf '{\n' > "$tmp/.server-install.json"
TYPE=auto
expect_failure "Invalid server install marker JSON: $tmp/.server-install.json" resolve_type_auto

printf '{"artifact":"server.jar","type":"paper","version":"1.21.8"}\n' > "$tmp/.server-install.json"
TYPE=auto
expect_failure "Incomplete server install marker: $tmp/.server-install.json missing build" resolve_type_auto
