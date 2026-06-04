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
  test "$1" = "cp"
  printf '%s\n' "$2" >> "$mc_calls"
  command cp "$archive" "$3"
}

reset_calls() {
  : > "$configure_calls"
  : > "$mc_calls"
}

assert_no_s3_calls() {
  test ! -s "$configure_calls"
  test ! -s "$mc_calls"
}

DATA_DIR="$tmp/success"
S3_BUCKET=bucket
WORLD_S3_KEY=prefix/world.zip
reset_calls
install_world
test "$(cat "$configure_calls")" = "world"
test "$(cat "$mc_calls")" = "s3/bucket/prefix/world.zip"
test -f "$DATA_DIR/world/level.dat"

DATA_DIR="$tmp/missing-bucket"
unset S3_BUCKET
WORLD_S3_KEY=prefix/world.zip
reset_calls
output="$(install_world 2>&1)"
printf '%s\n' "$output" | grep -q 'S3_BUCKET or WORLD_S3_KEY not set, skipping world install'
assert_no_s3_calls
test ! -e "$DATA_DIR/world"

DATA_DIR="$tmp/missing-key"
S3_BUCKET=bucket
unset WORLD_S3_KEY
reset_calls
output="$(install_world 2>&1)"
printf '%s\n' "$output" | grep -q 'S3_BUCKET or WORLD_S3_KEY not set, skipping world install'
assert_no_s3_calls
test ! -e "$DATA_DIR/world"

DATA_DIR="$tmp/existing-world"
S3_BUCKET=bucket
WORLD_S3_KEY=prefix/world.zip
mkdir -p "$DATA_DIR/world"
printf '%s\n' existing > "$DATA_DIR/world/level.dat"
reset_calls
output="$(install_world 2>&1)"
printf '%s\n' "$output" | grep -q 'World already exists, skipping world install'
assert_no_s3_calls
test "$(cat "$DATA_DIR/world/level.dat")" = "existing"
