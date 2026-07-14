#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh
source ./scripts/lib/s3_client.sh
source ./scripts/lib/world_paths.sh
source ./scripts/lib/content_assets.sh

calls="$tmp/calls"
: > "$calls"

configure_s3_client() {
  test "$1" = "datapacks"
}

s3_sync() {
  test "$1" = "s3/bucket/prefix"
  mkdir -p "$2"
  : > "$2/remote.zip"
  printf 'sync:%s\n' "$2" >> "$calls"
}

activate_dir() {
  test "${1##*/.datapacks-s3.*}" != "$1"
  test "$3" = "datapacks"
  printf 'activate:%s\n' "$2" >> "$calls"
}

run_datapack_path_case() {
  local name="$1"
  local level_name="${2:-}"
  local expected_world_name="$3"

  DATA_DIR="$tmp/${name}/data"
  DATAPACKS_ENABLED=true
  DATAPACKS_S3_BUCKET=bucket
  DATAPACKS_S3_PREFIX=prefix
  DATAPACKS_SYNC_ONCE=false
  DATAPACKS_REMOVE_EXTRA=false
  export DATAPACKS_SYNC_ONCE DATAPACKS_REMOVE_EXTRA

  if [[ -n "$level_name" ]]; then
    LEVEL_NAME="$level_name"
  else
    unset LEVEL_NAME
  fi

  mkdir -p "$DATA_DIR/${expected_world_name}"
  : > "$calls"

  install_datapacks >/dev/null 2>&1
  activate_datapacks >/dev/null 2>&1

  [[ "$(sed -n '1p' "$calls")" == "sync:${DATA_DIR}/.datapacks-s3."* ]]
  test "$(sed -n '2p' "$calls")" = "activate:$DATA_DIR/${expected_world_name}/datapacks"
}

run_datapack_path_case default "" world
run_datapack_path_case custom custom-world custom-world

unset LEVEL_NAME
