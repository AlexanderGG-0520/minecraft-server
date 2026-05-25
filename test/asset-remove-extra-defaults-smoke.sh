#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

asset_vars=(
  MODS_REMOVE_EXTRA
  PLUGINS_REMOVE_EXTRA
  CONFIGS_REMOVE_EXTRA
  DATAPACKS_REMOVE_EXTRA
  RESOURCEPACKS_REMOVE_EXTRA
)

test_defaults_are_safe() {
  local var
  for var in "${asset_vars[@]}"; do
    unset "${var}"
  done

  __SOURCED=1 source ./entrypoint.sh >/dev/null

  for var in "${asset_vars[@]}"; do
    test "${!var}" = "false"
  done
}

test_explicit_opt_in_is_preserved() {
  local var
  for var in "${asset_vars[@]}"; do
    export "${var}=true"
  done

  __SOURCED=1 source ./entrypoint.sh >/dev/null

  for var in "${asset_vars[@]}"; do
    test "${!var}" = "true"
  done
}

(
  test_defaults_are_safe
)

(
  test_explicit_opt_in_is_preserved
)
