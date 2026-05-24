#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh
source ./scripts/lib/runtime.sh
source ./scripts/lib/server_install.sh
source ./scripts/lib/s3_client.sh
source ./scripts/lib/world_install.sh

DATA_DIR="$tmp/data"
mkdir -p "$DATA_DIR"

test_no_server_marker_temps() {
  if find "$DATA_DIR" -maxdepth 1 -name '.server-install.json.tmp.*' -print -quit | grep -q .; then
    return 1
  fi
}

write_server_install_marker "server.jar" "paper" "1.21.8" "123"
jq -e '.artifact == "server.jar" and .type == "paper" and .version == "1.21.8" and .build == "123"' "$DATA_DIR/.server-install.json" >/dev/null
test "$(stat -c '%a' "$DATA_DIR/.server-install.json")" != "600"
test_no_server_marker_temps

curl() {
  local out=""
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -o)
        out="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  [[ -n "$out" ]] || return 99
  printf '%s\n' partial > "$out"
  return 7
}

set +e
(
  download_file_atomic "https://example.invalid/server.jar" "$DATA_DIR/server.jar" "test server.jar"
) >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 1
if find "$DATA_DIR" -maxdepth 1 -name '.server.jar.tmp.*' -print -quit | grep -q .; then
  exit 1
fi
test ! -e "$DATA_DIR/server.jar"

create_fixture_zip() {
  local archive="$1"
  local fixture_dir="$tmp/world-fixture"

  safe_rm_rf "$fixture_dir"
  mkdir -p "$fixture_dir/world"
  printf '%s\n' world > "$fixture_dir/world/level.dat"
  (cd "$fixture_dir" && zip -qr "$archive" world)
}

archive="$tmp/world.zip"
create_fixture_zip "$archive"

configure_mc_alias() {
  test "$1" = "world"
}

mc() {
  test "$1" = "cp"
  printf '%s\n' "$3" > "$tmp/world-archive-target.txt"
  command cp "$archive" "$3"
}

WORLD_S3_BUCKET=bucket
WORLD_S3_KEY=world.zip
touch "$DATA_DIR/reset-world.flag"
install_world

archive_target="$(cat "$tmp/world-archive-target.txt")"
case "$archive_target" in
  /tmp/world.*.zip) ;;
  *) echo "unexpected world archive target: $archive_target" >&2; exit 1 ;;
esac
test "$archive_target" != "/tmp/world.zip"
test ! -e "$archive_target"
test ! -e /tmp/world.zip
test -f "$DATA_DIR/world/level.dat"
