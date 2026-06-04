#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh
source ./scripts/lib/world_install.sh

archive="$tmp/world.zip"
fixture_dir="$tmp/fixture"
mkdir -p "$fixture_dir/world"
printf '%s\n' world > "$fixture_dir/world/level.dat"
(cd "$fixture_dir" && zip -qr "$archive" world)

configure_calls="$tmp/configure-calls"
mc_calls="$tmp/mc-calls"
: > "$configure_calls"
: > "$mc_calls"

configure_mc_alias() {
  printf '%s\n' "$1" >> "$configure_calls"
}

mc() {
  printf '%s\n' "$*" >> "$mc_calls"
  case "$1" in
    ls)
      test "$2" = "--json"
      case "${MC_LS_MODE:-single}" in
        single) printf '%s\n' '{"type":"file","key":"world.zip"}' ;;
        empty)
          printf '%s\n' '{"type":"file","key":"notes.txt"}'
          printf '%s\n' '{"type":"folder","key":"nested.zip/"}'
          ;;
        multiple)
          printf '%s\n' '{"type":"file","key":"first.zip"}'
          printf '%s\n' '{"type":"file","key":"second.zip"}'
          ;;
        *) return 99 ;;
      esac
      ;;
    cp)
      command cp "$archive" "$3"
      ;;
    *)
      return 99
      ;;
  esac
}

reset_calls() {
  : > "$configure_calls"
  : > "$mc_calls"
}

assert_no_s3_calls() {
  test ! -s "$configure_calls"
  test ! -s "$mc_calls"
}

DATA_DIR="$tmp/disabled-unset"
unset WORLDS_ENABLED
reset_calls
output="$(install_world 2>&1)"
printf '%s\n' "$output" | grep -q 'Worlds disabled'
assert_no_s3_calls
test ! -e "$DATA_DIR/world"

DATA_DIR="$tmp/disabled-false"
WORLDS_ENABLED=false
reset_calls
output="$(install_world 2>&1)"
printf '%s\n' "$output" | grep -q 'Worlds disabled'
assert_no_s3_calls
test ! -e "$DATA_DIR/world"

DATA_DIR="$tmp/success"
WORLDS_ENABLED=true
WORLDS_S3_BUCKET=bucket
WORLDS_S3_PREFIX=prefix/
MC_LS_MODE=single
reset_calls
install_world
test "$(cat "$configure_calls")" = "world"
test "$(sed -n '1p' "$mc_calls")" = "ls --json s3/bucket/prefix/"
case "$(sed -n '2p' "$mc_calls")" in
  "cp s3/bucket/prefix/world.zip /tmp/world."*.zip) ;;
  *) echo "unexpected world archive copy call" >&2; exit 1 ;;
esac
test -f "$DATA_DIR/world/level.dat"

DATA_DIR="$tmp/missing-bucket"
unset WORLDS_S3_BUCKET
WORLDS_S3_PREFIX=prefix
reset_calls
output="$(install_world 2>&1)"
printf '%s\n' "$output" | grep -q 'WORLDS_S3_BUCKET or WORLDS_S3_PREFIX not set, skipping world install'
assert_no_s3_calls
test ! -e "$DATA_DIR/world"

DATA_DIR="$tmp/missing-prefix"
WORLDS_S3_BUCKET=bucket
unset WORLDS_S3_PREFIX
reset_calls
output="$(install_world 2>&1)"
printf '%s\n' "$output" | grep -q 'WORLDS_S3_BUCKET or WORLDS_S3_PREFIX not set, skipping world install'
assert_no_s3_calls
test ! -e "$DATA_DIR/world"

DATA_DIR="$tmp/no-archive"
WORLDS_S3_BUCKET=bucket
WORLDS_S3_PREFIX=prefix
MC_LS_MODE=empty
reset_calls
set +e
output="$(install_world 2>&1)"
status=$?
set -e
test "$status" -eq 1
printf '%s\n' "$output" | grep -q 'No world archive found under s3://bucket/prefix'
test "$(cat "$configure_calls")" = "world"
test "$(cat "$mc_calls")" = "ls --json s3/bucket/prefix/"
test ! -e "$DATA_DIR/world"

DATA_DIR="$tmp/ambiguous-archive"
MC_LS_MODE=multiple
reset_calls
set +e
output="$(install_world 2>&1)"
status=$?
set -e
test "$status" -eq 1
printf '%s\n' "$output" | grep -q 'Ambiguous world archive source under s3://bucket/prefix'
test "$(cat "$configure_calls")" = "world"
test "$(cat "$mc_calls")" = "ls --json s3/bucket/prefix/"
test ! -e "$DATA_DIR/world"

DATA_DIR="$tmp/empty-world"
MC_LS_MODE=single
mkdir -p "$DATA_DIR/world"
reset_calls
install_world
test "$(cat "$configure_calls")" = "world"
test "$(sed -n '1p' "$mc_calls")" = "ls --json s3/bucket/prefix/"
test -f "$DATA_DIR/world/level.dat"

DATA_DIR="$tmp/existing-world"
WORLDS_S3_BUCKET=bucket
WORLDS_S3_PREFIX=prefix
MC_LS_MODE=single
mkdir -p "$DATA_DIR/world"
printf '%s\n' existing > "$DATA_DIR/world/level.dat"
reset_calls
output="$(install_world 2>&1)"
printf '%s\n' "$output" | grep -q 'World already exists, skipping world install'
assert_no_s3_calls
test "$(cat "$DATA_DIR/world/level.dat")" = "existing"
