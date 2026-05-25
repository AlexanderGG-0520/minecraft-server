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

reset_data_dir() {
  safe_rm_f "$tmp/server.jar"
  safe_rm_f "$tmp/.server-install.json"
  safe_rm_f "$tmp/.installed-forge-1.21.8-52.0.1"
  safe_rm_f "$tmp/.installed-neoforge-1.21.8-21.8.1"
  mkdir -p "$tmp/world" "$tmp/mods" "$tmp/plugins" "$tmp/config" "$tmp/datapacks" "$tmp/resourcepacks"
  printf '%s\n' world > "$tmp/world/level.dat"
  printf '%s\n' mod > "$tmp/mods/example.jar"
  printf '%s\n' plugin > "$tmp/plugins/example.jar"
  printf '%s\n' config > "$tmp/config/example.yml"
  printf '%s\n' datapack > "$tmp/datapacks/example.zip"
  printf '%s\n' resourcepack > "$tmp/resourcepacks/example.zip"
}

reset_data_dir
printf '%s\n' jar > "$tmp/server.jar"
write_server_install_marker "server.jar" "paper" "1.21.8" "123"
assert_server_install_matches "server.jar" "paper" "1.21.8" "123"
test -f "$tmp/server.jar"

expect_failure "type current=paper requested=vanilla" \
  assert_server_install_matches "server.jar" "vanilla" "1.21.8" ""
test -f "$tmp/server.jar"
test -f "$tmp/.server-install.json"

expect_failure "version current=1.21.8 requested=1.21.9" \
  assert_server_install_matches "server.jar" "paper" "1.21.9" "123"
test -f "$tmp/server.jar"
test -f "$tmp/.server-install.json"

expect_failure "build current=123 requested=124" \
  assert_server_install_matches "server.jar" "paper" "1.21.8" "124"
test -f "$tmp/server.jar"
test -f "$tmp/.server-install.json"

FORCE_REINSTALL=true
if assert_server_install_matches "server.jar" "paper" "1.21.8" "124"; then
  echo "FAIL: forced reinstall mismatch unexpectedly matched" >&2
  exit 1
fi
unset FORCE_REINSTALL

test ! -e "$tmp/server.jar"
test ! -e "$tmp/.server-install.json"
test -f "$tmp/world/level.dat"
test -f "$tmp/mods/example.jar"
test -f "$tmp/plugins/example.jar"
test -f "$tmp/config/example.yml"
test -f "$tmp/datapacks/example.zip"
test -f "$tmp/resourcepacks/example.zip"

printf '%s\n' jar > "$tmp/server.jar"
assert_server_install_matches "server.jar" "paper" "1.21.8" "123"
test -f "$tmp/server.jar"

write_server_install_marker "server.jar" "spigot" "1.21.8" ""
TYPE=auto
resolve_type_auto
test "$TYPE" = "spigot"

printf '{\n' > "$tmp/.server-install.json"
TYPE=auto
expect_failure "Invalid server install marker JSON: $tmp/.server-install.json" resolve_type_auto
