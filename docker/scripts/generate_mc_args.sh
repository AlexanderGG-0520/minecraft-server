#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$1] $2"
}

MC_ARGS_FILE="/data/mc.args"

# ------------------------------------------------------------
# Skip if mc.args already exists
# ------------------------------------------------------------
if [[ -f "$MC_ARGS_FILE" ]]; then
  log INFO "mc.args already exists, skipping auto-generation"
  exit 0
fi

log INFO "Generating default mc.args"

# ------------------------------------------------------------
# Defaults
# ------------------------------------------------------------
: "${SERVER_PORT:=25565}"
: "${ENABLE_GUI:=false}"

ARGS=()

# ------------------------------------------------------------
# Common args
# ------------------------------------------------------------
ARGS+=("--port")
ARGS+=("${SERVER_PORT}")

# ------------------------------------------------------------
# GUI control
# ------------------------------------------------------------
if [[ "${ENABLE_GUI}" == "false" ]]; then
  ARGS+=("nogui")
fi

# ------------------------------------------------------------
# Write mc.args
# ------------------------------------------------------------
printf "%s " "${ARGS[@]}" | sed 's/ $//' > "$MC_ARGS_FILE"

chmod 644 "$MC_ARGS_FILE"

log INFO "mc.args generated successfully: $(cat "$MC_ARGS_FILE")"
