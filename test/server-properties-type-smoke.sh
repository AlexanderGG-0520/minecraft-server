#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/runtime.sh
source ./scripts/lib/server_properties.sh

DATA_DIR="$tmp/data"
mkdir -p "$DATA_DIR"

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

unset TYPE
test "$(server_properties_type)" = ""
output="$(ensure_server_properties 2>&1)"
printf '%s\n' "$output" | grep -F "TYPE= does not use server.properties, skipping bootstrap" >/dev/null
test ! -f "$DATA_DIR/server.properties"
expect_failure "bootstrap_server_properties: unsupported TYPE=" bootstrap_server_properties

TYPE=velocity
output="$(ensure_server_properties 2>&1)"
printf '%s\n' "$output" | grep -F "TYPE=velocity does not use server.properties, skipping bootstrap" >/dev/null
test ! -f "$DATA_DIR/server.properties"

TYPE=paper
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' "touch \"\$(dirname \"\$2\")/server.properties\""
} > "$tmp/java"
chmod +x "$tmp/java"
PATH="$tmp:$PATH"
touch "$DATA_DIR/server.jar"
ensure_server_properties
test -f "$DATA_DIR/server.properties"
