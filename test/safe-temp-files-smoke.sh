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
source ./scripts/lib/world_paths.sh
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

s3_tmp="$tmp/s3tmp"
mkdir -p "$s3_tmp"
TMPDIR="$s3_tmp"
export TMPDIR

assert_s3_tmp_empty() {
  ! find "$TMPDIR" -mindepth 1 -print -quit | grep -q .
}

mc() {
  test "$1" = "find"
  test "$3" = "--print"
  test "$4" = "{}"
  case "${MC_MODE:-success}" in
    success) printf '%s\n' "${2%/}/remote.jar" ;;
    empty) return 0 ;;
    fail) return 7 ;;
    *) return 99 ;;
  esac
}

MC_MODE=success ensure_s3_source_nonempty_for_remove "s3/bucket/prefix" "mods"
assert_s3_tmp_empty

set +e
output="$(MC_MODE=fail ensure_s3_source_nonempty_for_remove "s3/bucket/prefix" "mods" 2>&1)"
status=$?
set -e
test "$status" -eq 1
printf '%s\n' "$output" | grep -q 'Failed to list mods source before remove sync: s3/bucket/prefix'
assert_s3_tmp_empty

set +e
output="$(MC_MODE=empty ensure_s3_source_nonempty_for_remove "s3/bucket/prefix" "mods" 2>&1)"
status=$?
set -e
test "$status" -eq 1
printf '%s\n' "$output" | grep -q 'mods remove_extra requested but S3 source is empty: s3/bucket/prefix'
assert_s3_tmp_empty

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

snapshot_world_install_temps() {
  find /tmp -maxdepth 1 \( -name 'world.*.zip' -o -name 'world-extract.*' \) -print | sort
}

assert_world_install_temps_unchanged() {
  diff -u "$world_temp_snapshot" <(snapshot_world_install_temps)
  test ! -e /tmp/world.zip
}

configure_mc_alias() {
  test "$1" = "world"
}

mc() {
  case "$1" in
    ls)
      test "$2" = "--json"
      test "$3" = "s3/bucket/world/"
      printf '%s\n' '{"type":"file","key":"world.zip"}'
      ;;
    cp)
      test "$2" = "s3/bucket/world/world.zip"
      printf '%s\n' "$3" > "$tmp/world-archive-target.txt"
      command cp "$archive" "$3"
      ;;
    *)
      return 99
      ;;
  esac
}

WORLDS_ENABLED=true
WORLDS_S3_BUCKET=bucket
WORLDS_S3_PREFIX=world
world_temp_snapshot="$tmp/world-temp-snapshot.txt"
snapshot_world_install_temps > "$world_temp_snapshot"
touch "$DATA_DIR/reset-world.flag"
install_world

archive_target="$(cat "$tmp/world-archive-target.txt")"
case "$archive_target" in
  /tmp/world.*.zip) ;;
  *) echo "unexpected world archive target: $archive_target" >&2; exit 1 ;;
esac
test "$archive_target" != "/tmp/world.zip"
test ! -e "$archive_target"
assert_world_install_temps_unchanged
test -f "$DATA_DIR/world/level.dat"

archive="$tmp/invalid-world.zip"
printf '%s\n' "not a zip" > "$archive"
DATA_DIR="$tmp/invalid-world-data"
mkdir -p "$DATA_DIR/world"
printf '%s\n' old-world > "$DATA_DIR/world/level.dat"
touch "$DATA_DIR/reset-world.flag"

set +e
output="$(install_world 2>&1)"
status=$?
set -e
test "$status" -eq 1
printf '%s\n' "$output" | grep -q 'Failed to extract world archive with unzip'
archive_target="$(cat "$tmp/world-archive-target.txt")"
test ! -e "$archive_target"
assert_world_install_temps_unchanged
test -f "$DATA_DIR/reset-world.flag"
test "$(cat "$DATA_DIR/world/level.dat")" = "old-world"
