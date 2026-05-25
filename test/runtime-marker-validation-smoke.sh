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

marker="$tmp/.server-install.json"

write_server_install_marker "server.jar" "paper" "1.21.8" "123"
assert_server_install_matches "server.jar" "paper" "1.21.8" "123"

printf '{\n' > "$marker"
expect_failure "Invalid server install marker JSON: $marker" \
  assert_server_install_matches "server.jar" "paper" "1.21.8"

printf '{"artifact":"server.jar","type":"paper","build":"123"}\n' > "$marker"
expect_failure "Incomplete server install marker: $marker missing version" \
  assert_server_install_matches "server.jar" "paper" "1.21.8"

printf '{"artifact":"","type":"paper","version":"1.21.8","build":"123"}\n' > "$marker"
expect_failure "Invalid server install marker: $marker field artifact must not be empty" \
  assert_server_install_matches "server.jar" "paper" "1.21.8"

printf '{"artifact":"server.jar","type":null,"version":"1.21.8","build":"123"}\n' > "$marker"
expect_failure "Incomplete server install marker: $marker missing type" \
  assert_server_install_matches "server.jar" "paper" "1.21.8"

printf '{"artifact":"server.jar","type":"paper","version":"1.21.8","build":null}\n' > "$marker"
expect_failure "Incomplete server install marker: $marker missing build" \
  assert_server_install_matches "server.jar" "paper" "1.21.8"

printf '{"artifact":"server.jar","type":"unknown","version":"1.21.8","build":"123"}\n' > "$marker"
expect_failure "Invalid server install marker: $marker unsupported type unknown" \
  assert_server_install_matches "server.jar" "paper" "1.21.8"

printf '{"artifact":"other.jar","type":"paper","version":"1.21.8","build":"123"}\n' > "$marker"
expect_failure "Invalid server install marker: $marker unsupported artifact other.jar" \
  assert_server_install_matches "server.jar" "paper" "1.21.8"

printf '{\n' > "$marker"
TYPE=auto
expect_failure "Invalid server install marker JSON: $marker" resolve_type_auto

printf '{"artifact":"server.jar","type":"paper","version":"","build":"123"}\n' > "$marker"
TYPE=auto
expect_failure "Invalid server install marker: $marker field version must not be empty" resolve_type_auto

printf '{"artifact":"server.jar","type":"unknown","version":"1.21.8","build":"123"}\n' > "$marker"
TYPE=auto
expect_failure "Invalid server install marker: $marker unsupported type unknown" resolve_type_auto

write_server_install_marker "server.jar" "vanilla" "1.21.8"
test "$(read_server_install_marker_field "$marker" build)" = ""
