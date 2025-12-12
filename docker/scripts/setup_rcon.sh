#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$1] $2"
}

SERVER_PROPERTIES="/data/server.properties"

: "${ENABLE_RCON:=false}"
: "${RCON_PORT:=25575}"

# ------------------------------------------------------------
# Skip if RCON disabled
# ------------------------------------------------------------
if [[ "${ENABLE_RCON}" != "true" ]]; then
  log INFO "RCON disabled"
  return 0 2>/dev/null || exit 0
fi

log INFO "Enabling RCON"

# ------------------------------------------------------------
# Generate RCON_PASSWORD if missing
# ------------------------------------------------------------
if [[ -z "${RCON_PASSWORD:-}" ]]; then
  RCON_PASSWORD="$(openssl rand -hex 16)"
  export RCON_PASSWORD
  log INFO "Generated random RCON_PASSWORD"
fi

# ------------------------------------------------------------
# Ensure server.properties exists
# ------------------------------------------------------------
if [[ ! -f "$SERVER_PROPERTIES" ]]; then
  log ERROR "server.properties not found, cannot configure RCON"
  exit 1
fi

# ------------------------------------------------------------
# Apply RCON settings (idempotent)
# ------------------------------------------------------------
apply_prop() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" "$SERVER_PROPERTIES"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$SERVER_PROPERTIES"
  else
    echo "${key}=${value}" >> "$SERVER_PROPERTIES"
  fi
}

apply_prop "enable-rcon" "true"
apply_prop "rcon.port" "${RCON_PORT}"
apply_prop "rcon.password" "${RCON_PASSWORD}"

log INFO "RCON configured successfully"
