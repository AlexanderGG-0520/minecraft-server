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
case "$TYPE_LOWER" in
  fabric)
    [[ -f /data/fabric-server-launch.jar ]] \
      || fatal "Fabric launcher not found"
    ;;
  quilt)
    [[ -f /data/quilt-server-launch.jar ]] \
      || fatal "Quilt launcher not found"
    ;;
  forge|neoforge)
    ls /data/forge-*-server.jar /data/run.sh >/dev/null 2>&1 \
      || fatal "Forge/NeoForge server not found"
    ;;
  vanilla|paper|purpur)
    [[ -f /data/server.jar ]] \
      || fatal "server.jar not found"
    ;;
  velocity)
    [[ -f /data/velocity.jar ]] \
      || fatal "velocity.jar not found"
    ;;
  bungeecord)
    [[ -f /data/bungeecord.jar ]] \
      || fatal "bungeecord.jar not found"
    ;;
  waterfall)
    [[ -f /data/waterfall.jar ]] \
      || fatal "waterfall.jar not found"
    ;;
  *)
    fatal "Unhandled TYPE post-check: $TYPE_LOWER"
    ;;
esac

log INFO "Server binary preparation completed successfully"
