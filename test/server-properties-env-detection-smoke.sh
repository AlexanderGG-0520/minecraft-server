#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail_if_present() {
  local pattern="$1"
  local file="$2"

  if grep -F "$pattern" "$file" >/dev/null; then
    echo "FAIL: unexpected property matching ${pattern}" >&2
    exit 1
  fi
}

run_internal_defaults_are_not_env_overrides() {
  DATA_DIR="$tmp/internal-defaults"
  APPLY_SERVER_PROPERTIES_DIFF=true
  # shellcheck disable=SC2034  # Intentionally non-exported to mimic entrypoint internal defaults.
  ENABLE_RCON=false
  # shellcheck disable=SC2034  # Intentionally non-exported to mimic entrypoint internal defaults.
  RCON_PORT=25575
  # shellcheck disable=SC2034  # Intentionally non-exported to mimic entrypoint internal defaults.
  RCON_PASSWORD=
  # shellcheck disable=SC2034  # Intentionally non-exported to mimic entrypoint internal defaults.
  ONLINE_MODE=true
  # shellcheck disable=SC2034  # Intentionally non-exported to mimic entrypoint internal defaults.
  SERVER_PORT=25565
  # shellcheck disable=SC2034  # Intentionally non-exported to mimic entrypoint internal defaults.
  SERVER_IP=

  source ./scripts/lib/logging.sh
  source ./scripts/lib/runtime.sh
  source ./scripts/lib/server_properties.sh

  mkdir -p "$DATA_DIR"
  cat > "$DATA_DIR/server.properties" <<'PROPS'
difficulty=hard
custom-key=custom-value
PROPS

  apply_server_properties_diff >/dev/null 2>&1

  grep -Fx 'difficulty=hard' "$DATA_DIR/server.properties" >/dev/null
  grep -Fx 'custom-key=custom-value' "$DATA_DIR/server.properties" >/dev/null
  fail_if_present 'enable-rcon=' "$DATA_DIR/server.properties"
  fail_if_present 'rcon.port=' "$DATA_DIR/server.properties"
  fail_if_present 'rcon.password=' "$DATA_DIR/server.properties"
  fail_if_present 'online-mode=' "$DATA_DIR/server.properties"
  fail_if_present 'server-port=' "$DATA_DIR/server.properties"
  fail_if_present 'server-ip=' "$DATA_DIR/server.properties"
}

run_canonical_env_wins_over_alias() {
  DATA_DIR="$tmp/alias-priority"
  APPLY_SERVER_PROPERTIES_DIFF=true
  LEVEL=alias-world
  LEVEL_NAME=canonical-world
  SEED=alias-seed
  LEVEL_SEED=canonical-seed
  MODE=adventure
  GAMEMODE=creative
  RESOURCE_PACK_ENFORCE=false
  REQUIRE_RESOURCE_PACK=true
  export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF LEVEL LEVEL_NAME SEED LEVEL_SEED
  export MODE GAMEMODE RESOURCE_PACK_ENFORCE REQUIRE_RESOURCE_PACK

  source ./scripts/lib/logging.sh
  source ./scripts/lib/runtime.sh
  source ./scripts/lib/server_properties.sh

  mkdir -p "$DATA_DIR"
  cat > "$DATA_DIR/server.properties" <<'PROPS'
level-name=existing
level-seed=existing
gamemode=survival
require-resource-pack=false
PROPS

  apply_server_properties_diff >/dev/null 2>&1

  grep -Fx 'level-name=canonical-world' "$DATA_DIR/server.properties" >/dev/null
  grep -Fx 'level-seed=canonical-seed' "$DATA_DIR/server.properties" >/dev/null
  grep -Fx 'gamemode=creative' "$DATA_DIR/server.properties" >/dev/null
  grep -Fx 'require-resource-pack=true' "$DATA_DIR/server.properties" >/dev/null
}

case "${1:-}" in
  internal-defaults)
    run_internal_defaults_are_not_env_overrides
    ;;
  alias-priority)
    run_canonical_env_wins_over_alias
    ;;
  "")
    bash "$0" internal-defaults
    bash "$0" alias-priority
    ;;
  *)
    echo "Unknown test case: $1" >&2
    exit 1
    ;;
esac
