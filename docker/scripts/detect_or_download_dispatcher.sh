#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$1] $2"
}

fatal() {
  log ERROR "$1"
  exit 1
}

# ------------------------------------------------------------
# Normalize TYPE
# ------------------------------------------------------------
TYPE_LOWER="$(echo "${TYPE:-}" | tr '[:upper:]' '[:lower:]')"

[[ -n "$TYPE_LOWER" ]] || fatal "TYPE is not set"

# ------------------------------------------------------------
# Supported server types
# ------------------------------------------------------------
SUPPORTED_TYPES=(
  vanilla
  fabric
  forge
  neoforge
  paper
  purpur
  velocity
  bungeecord
  waterfall
)

if ! printf '%s\n' "${SUPPORTED_TYPES[@]}" | grep -qx "$TYPE_LOWER"; then
  fatal "Unsupported server TYPE: $TYPE_LOWER"
fi

# ------------------------------------------------------------
# Resolve script path
# ------------------------------------------------------------
SCRIPT="/opt/mc/scripts/detect_or_download_${TYPE_LOWER}.sh"

[[ -f "$SCRIPT" ]] || fatal "Missing detect script: $SCRIPT"

log INFO "Running server binary preparation for TYPE=$TYPE_LOWER"

chmod +x "$SCRIPT"
"$SCRIPT"

# ------------------------------------------------------------
# Post-check: ensure something exists
# ------------------------------------------------------------
if ! ls /data/*.jar /data/run.sh >/dev/null 2>&1; then
  fatal "Server binary preparation finished, but no launchable files found in /data"
fi

log INFO "Server binary preparation completed successfully"
