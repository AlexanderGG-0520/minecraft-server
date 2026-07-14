#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -r -- "${tmp}"' EXIT
source "${root}/scripts/lib/logging.sh"
source "${root}/scripts/lib/filesystem.sh"
source "${root}/scripts/lib/world_paths.sh"
source "${root}/scripts/lib/content_assets.sh"

configure_s3_client() { test "$1" = datapacks; }
s3_sync() { test "$1" = s3/bucket/prefix; cp -a "${S3_FIXTURE}/." "$2/"; }

run_case() {
  local name="$1" local_file="$2" s3_file="$3" expected="$4"
  DATA_DIR="${tmp}/${name}/data"; INPUT_DATAPACKS_DIR="${tmp}/${name}/local"; S3_FIXTURE="${tmp}/${name}/s3"
  DATAPACKS_ENABLED=true; DATAPACKS_S3_BUCKET=bucket; DATAPACKS_S3_PREFIX=prefix; LEVEL_NAME="${5:-world}"
  mkdir -p "${DATA_DIR}/$(minecraft_world_name)/datapacks" "${INPUT_DATAPACKS_DIR}" "${S3_FIXTURE}"
  printf sentinel > "${DATA_DIR}/$(minecraft_world_name)/datapacks/old"
  [[ "$local_file" != none ]] && : > "${INPUT_DATAPACKS_DIR}/${local_file}"
  [[ "$s3_file" != none ]] && : > "${S3_FIXTURE}/${s3_file}"
  install_datapacks
  if [[ "$expected" == fail ]]; then
    set +e; output="$(activate_datapacks 2>&1)"; status=$?; set -e
    test "$status" -ne 0; printf '%s' "$output" | grep -F 'Datapack source conflict'
    test "$(cat "${DATA_DIR}/$(minecraft_world_name)/datapacks/old")" = sentinel
  else
    activate_datapacks
    if [[ "$expected" == preserve ]]; then test -f "${DATA_DIR}/$(minecraft_world_name)/datapacks/old"; else test -f "${DATA_DIR}/$(minecraft_world_name)/datapacks/${expected}"; test ! -f "${DATA_DIR}/$(minecraft_world_name)/datapacks/old"; fi
  fi
  ! find "${DATA_DIR}" -maxdepth 1 -name '.datapacks-s3.*' -print -quit | grep -q .
}

run_case empty none none preserve
run_case local local.zip none local.zip custom
run_case s3 none remote.zip remote.zip -dash
run_case conflict local.zip remote.zip fail

DATA_DIR="${tmp}/failure/data"; INPUT_DATAPACKS_DIR="${tmp}/failure/local"; DATAPACKS_ENABLED=true; DATAPACKS_S3_BUCKET=bucket; DATAPACKS_S3_PREFIX=prefix; LEVEL_NAME=world
mkdir -p "${DATA_DIR}/world/datapacks" "${INPUT_DATAPACKS_DIR}"; printf sentinel > "${DATA_DIR}/world/datapacks/old"; : > "${INPUT_DATAPACKS_DIR}/local.zip"
s3_sync() { return 7; }
set +e; install_datapacks; status=$?; set -e
test "$status" -ne 0; test "$(cat "${DATA_DIR}/world/datapacks/old")" = sentinel; ! find "${DATA_DIR}" -maxdepth 1 -name '.datapacks-s3.*' -print -quit | grep -q .
