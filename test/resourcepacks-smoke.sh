#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh
source ./scripts/lib/s3_client.sh
source ./scripts/lib/content_assets.sh

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
    mirror)
      mkdir -p "$4"
      printf '%s\n' pack > "$4/example.zip"
      ;;
    find)
      printf '%s\n' "$2/example.zip"
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

DATA_DIR="$tmp/data"
mkdir -p "$DATA_DIR"

INPUT_RESOURCEPACKS_DIR="$tmp/input-resourcepacks"
RESOURCEPACKS_ENABLED=true
RESOURCEPACKS_S3_BUCKET=bucket
RESOURCEPACKS_S3_PREFIX=resourcepacks
unset RESOURCEPACKS_SYNC_ONCE
unset RESOURCEPACKS_REMOVE_EXTRA
unset RESOURCEPACKS_AUTO_APPLY
unset RESOURCEPACK_URL
reset_calls
install_resourcepacks
test "$(cat "$configure_calls")" = "resourcepacks"
test "$(cat "$mc_calls")" = "mirror --overwrite s3/bucket/resourcepacks $INPUT_RESOURCEPACKS_DIR"
test -f "$INPUT_RESOURCEPACKS_DIR/example.zip"
test ! -d "$INPUT_RESOURCEPACKS_DIR/resourcepacks"

INPUT_RESOURCEPACKS_DIR="$tmp/unset-resourcepacks"
unset RESOURCEPACKS_S3_BUCKET
RESOURCEPACKS_S3_PREFIX=resourcepacks
reset_calls
output="$(install_resourcepacks 2>&1)"
printf '%s\n' "$output" | grep -q 'RESOURCEPACKS_S3_BUCKET not set, skipping resourcepacks'
assert_no_s3_calls
test ! -e "$INPUT_RESOURCEPACKS_DIR"

INPUT_RESOURCEPACKS_DIR="$tmp/empty-resourcepacks"
mkdir -p "$INPUT_RESOURCEPACKS_DIR"
DATA_DIR="$tmp/activation-data"
mkdir -p "$DATA_DIR"
output="$(activate_resourcepacks 2>&1)"
printf '%s\n' "$output" | grep -q "resourcepacks directory is empty ($INPUT_RESOURCEPACKS_DIR), skipping activation"
test ! -e "$DATA_DIR/resourcepacks"

TYPE=fabric
PLUGINS_ENABLED=true
unset PLUGINS_S3_BUCKET
output="$({ install_plugins; activate_plugins; } 2>&1)"
test "$(printf '%s\n' "$output" | grep -c 'Install plugins (Paper | Purpur | Mohist | Taiyitist | Youer | Velocity only)')" -eq 1
