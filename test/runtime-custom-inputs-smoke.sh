#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp}"' EXIT

source "${root}/scripts/lib/logging.sh"
source "${root}/scripts/lib/filesystem.sh"
source "${root}/scripts/lib/world_paths.sh"
source "${root}/scripts/lib/content_assets.sh"
source "${root}/scripts/lib/mods.sh"

DATA_DIR="${tmp}/data"
TYPE=paper
MODS_ENABLED=true
PLUGINS_ENABLED=true
CONFIGS_ENABLED=true
DATAPACKS_ENABLED=true
RESOURCEPACKS_ENABLED=true
LEVEL_NAME=world
mkdir -p "${DATA_DIR}/world"

reset_inputs() {
  unset INPUT_MODS_DIR INPUT_PLUGINS_DIR INPUT_CONFIG_DIR INPUT_DATAPACKS_DIR INPUT_RESOURCEPACKS_DIR
  unset INPUT_MODS_DIR_CONFIGURED INPUT_PLUGINS_DIR_CONFIGURED INPUT_CONFIG_DIR_CONFIGURED
  unset INPUT_DATAPACKS_DIR_CONFIGURED INPUT_RESOURCEPACKS_DIR_CONFIGURED
}

set_input() {
  local variable="$1"
  local value="$2"
  printf -v "${variable}" '%s' "${value}"
  printf -v "${variable}_CONFIGURED" '%s' true
}

hash_tree() {
  (cd -- "$1" && find . -type f -print0 | sort -z | xargs -0r sha256sum)
}

assert_custom_selection() {
  local name="$1"
  local variable="$2"
  local source="$3"
  local destination="$4"
  local function="$5"
  local custom_file="$6"
  local source_hash

  mkdir -p -- "${source}"
  printf '%s custom\n' "${name}" > "${source}/${custom_file}"
  source_hash="$(hash_tree "${source}")"
  set_input "${variable}" "${source}"
  "${function}"
  test "$(cat -- "${destination}/${custom_file}")" = "${name} custom"
  test "$(hash_tree "${source}")" = "${source_hash}"
}

reset_inputs
assert_custom_selection mods INPUT_MODS_DIR "${tmp}/custom mods/-mods" "${DATA_DIR}/mods" activate_mods custom-mod.jar
test ! -e "${DATA_DIR}/mods/default-mod.jar"

reset_inputs
assert_custom_selection plugins INPUT_PLUGINS_DIR "${tmp}/custom plugins" "${DATA_DIR}/plugins" activate_plugins custom-plugin.jar
test ! -e "${DATA_DIR}/plugins/default-plugin.jar"

reset_inputs
mkdir -p "${tmp}/custom config/nested"
printf 'config custom\n' > "${tmp}/custom config/nested/custom.conf"
set_input INPUT_CONFIG_DIR "${tmp}/custom config"
activate_configs
test "$(cat -- "${DATA_DIR}/config/nested/custom.conf")" = 'config custom'
test ! -e "${DATA_DIR}/config/default.conf"

reset_inputs
mkdir -p "${tmp}/custom datapacks"
printf 'datapack custom\n' > "${tmp}/custom datapacks/custom.zip"
set_input INPUT_DATAPACKS_DIR "${tmp}/custom datapacks"
activate_datapacks
test "$(cat -- "${DATA_DIR}/world/datapacks/custom.zip")" = 'datapack custom'
test ! -e "${DATA_DIR}/world/datapacks/default.zip"

# Default selection remains the documented hard-coded source when no override is configured.
reset_inputs
activate_mods
test "${CONTENT_INPUT_SOURCE}" = /mods
activate_configs
test "${CONTENT_INPUT_SOURCE}" = /config
reset_inputs
TYPE=paper
activate_plugins
test "${CONTENT_INPUT_SOURCE}" = /plugins
reset_inputs
activate_datapacks
test "${CONTENT_INPUT_SOURCE}" = /datapacks

empty_input_preserves_destination() {
  local name="$1" variable="$2" source="$3" destination="$4" function="$5"
  mkdir -p -- "${source}" "${destination}"
  printf '%s sentinel\n' "${name}" > "${destination}/sentinel"
  set_input "${variable}" "${source}"
  "${function}"
  test "$(cat -- "${destination}/sentinel")" = "${name} sentinel"
}

reset_inputs
empty_input_preserves_destination mods INPUT_MODS_DIR "${tmp}/empty-mods" "${DATA_DIR}/mods" activate_mods
reset_inputs
empty_input_preserves_destination plugins INPUT_PLUGINS_DIR "${tmp}/empty-plugins" "${DATA_DIR}/plugins" activate_plugins
reset_inputs
empty_input_preserves_destination config INPUT_CONFIG_DIR "${tmp}/empty-config" "${DATA_DIR}/config" activate_configs
reset_inputs
empty_input_preserves_destination datapacks INPUT_DATAPACKS_DIR "${tmp}/empty-datapacks" "${DATA_DIR}/world/datapacks" activate_datapacks

assert_invalid_preserves_destination() {
  local name="$1" variable="$2" source="$3" destination="$4" function="$5"
  local output status
  mkdir -p -- "${destination}"
  printf '%s sentinel\n' "${name}" > "${destination}/invalid-sentinel"
  set_input "${variable}" "${source}"
  set +e
  output="$(${function} 2>&1)"
  status=$?
  set -e
  test "${status}" -ne 0
  printf '%s\n' "${output}" | grep -F "${variable}" >/dev/null
  test "$(cat -- "${destination}/invalid-sentinel")" = "${name} sentinel"
}

reset_inputs
assert_invalid_preserves_destination mods INPUT_MODS_DIR "${tmp}/missing-mods" "${DATA_DIR}/mods" activate_mods
reset_inputs
assert_invalid_preserves_destination plugins INPUT_PLUGINS_DIR "${tmp}/missing-plugins" "${DATA_DIR}/plugins" activate_plugins
reset_inputs
assert_invalid_preserves_destination config INPUT_CONFIG_DIR "${tmp}/missing-config" "${DATA_DIR}/config" activate_configs
reset_inputs
assert_invalid_preserves_destination datapacks INPUT_DATAPACKS_DIR "${tmp}/missing-datapacks" "${DATA_DIR}/world/datapacks" activate_datapacks

printf 'not a directory\n' > "${tmp}/not-a-directory"
reset_inputs
assert_invalid_preserves_destination mods INPUT_MODS_DIR "${tmp}/not-a-directory" "${DATA_DIR}/mods" activate_mods

# The current user can reliably test unreadability only when it lacks root bypass.
if [[ "$(id -u)" -ne 0 ]]; then
  mkdir -p "${tmp}/unreadable"
  chmod 000 "${tmp}/unreadable"
  reset_inputs
  assert_invalid_preserves_destination config INPUT_CONFIG_DIR "${tmp}/unreadable" "${DATA_DIR}/config" activate_configs
  chmod 700 "${tmp}/unreadable"
fi

assert_overlap_rejected() {
  local variable="$1" source="$2" destination="$3" function="$4"
  local output status
  mkdir -p -- "${source}" "${destination}"
  printf sentinel > "${destination}/overlap-sentinel"
  set_input "${variable}" "${source}"
  set +e
  output="$(${function} 2>&1)"
  status=$?
  set -e
  test "${status}" -ne 0
  printf '%s\n' "${output}" | grep -F 'must not overlap' >/dev/null
  test -f "${destination}/overlap-sentinel"
}

reset_inputs
set_input INPUT_MODS_DIR "${DATA_DIR}/mods"
mkdir -p "${DATA_DIR}/mods"
printf active > "${DATA_DIR}/mods/active.jar"
activate_mods
test "$(cat -- "${DATA_DIR}/mods/active.jar")" = active

reset_inputs
assert_overlap_rejected INPUT_MODS_DIR "${DATA_DIR}" "${DATA_DIR}/mods" activate_mods
reset_inputs
mkdir -p "${DATA_DIR}/config/input"
assert_overlap_rejected INPUT_CONFIG_DIR "${DATA_DIR}/config/input" "${DATA_DIR}/config" activate_configs

# Resourcepacks already uses INPUT_RESOURCEPACKS_DIR; exercise the same resolver without changing delivery behavior.
reset_inputs
mkdir -p "${tmp}/resourcepacks custom"
printf pack > "${tmp}/resourcepacks custom/pack.zip"
set_input INPUT_RESOURCEPACKS_DIR "${tmp}/resourcepacks custom"
activate_resourcepacks
test -f "${DATA_DIR}/resourcepacks/pack.zip"

reset_inputs
