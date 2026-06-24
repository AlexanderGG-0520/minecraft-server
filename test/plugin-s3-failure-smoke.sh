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

configure_s3_client() {
  test "$1" = "plugins"
}

s3_list_paths() {
  test "$1" = "s3/bucket/prefix/"
  printf '%s\n' "s3/bucket/prefix/existing.jar"
}

s3_cp() {
  test "$1" = "s3/bucket/prefix/existing.jar"
  printf '%s\n' replacement > "$2"
  return 7
}

assert_existing_jar_intact() {
  local plugins_dir="$1"

  test -f "$plugins_dir/existing.jar"
  test "$(cat "$plugins_dir/existing.jar")" = "original"

  if find "$plugins_dir" -maxdepth 1 -type f -name '.*.tmp.*' -print -quit | grep -q .; then
    echo "FAIL: expected no temp jar files in ${plugins_dir}" >&2
    exit 1
  fi
}

run_failed_replacement_case() {
  local name="$1"
  local strict="$2"
  local expected_status="$3"
  local plugins_dir="$tmp/${name}/plugins"

  mkdir -p "$plugins_dir"
  printf '%s\n' original > "$plugins_dir/existing.jar"

  TYPE=paper
  PLUGINS_ENABLED=true
  PLUGINS_S3_BUCKET=bucket
  PLUGINS_S3_PREFIX=prefix
  PLUGINS_SYNC_ONCE=false
  PLUGINS_REMOVE_EXTRA=false
  PLUGINS_STRICT="$strict"
  PLUGINS_MAX_ERRORS=50
  S3_RETRY_MAX=1
  S3_RETRY_SLEEP=0
  INPUT_PLUGINS_DIR="$plugins_dir"

  set +e
  ( install_plugins ) >/dev/null 2>&1
  local status=$?
  set -e

  test "$status" -eq "$expected_status"
  assert_existing_jar_intact "$plugins_dir"
}

run_failed_replacement_case non-strict false 0
run_failed_replacement_case strict true 1
