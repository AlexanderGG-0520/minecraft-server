#!/usr/bin/env bash
set -Eeuo pipefail

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] [$1] $2"; }

DATA_DIR=/data
LOG_FILE="${DATA_DIR}/logs/latest.log"
READY_FILE="${DATA_DIR}/.ready"

JVM_ARGS="${JVM_ARGS:-}"
MC_ARGS="${MC_ARGS:-}"

mkdir -p "${DATA_DIR}/logs"
rm -f "${READY_FILE}"

# ------------------------------------------------------------
# Readiness watcher (log-based)
# ------------------------------------------------------------
(
  until [[ -f "${LOG_FILE}" ]]; do sleep 1; done
  tail -Fn0 "${LOG_FILE}" | while read -r line; do
    if echo "$line" | grep -q 'Done (.*)! For help, type "help"'; then
      log INFO "Server READY"
      touch "${READY_FILE}"
      break
    fi
  done
) &

# ------------------------------------------------------------
# Shutdown hook (PID1)
# ------------------------------------------------------------
shutdown() {
  log INFO "Shutdown signal received"
  if command -v rcon-cli >/dev/null 2>&1; then
    rcon-cli stop || true
  fi
  exit 0
}
trap shutdown SIGTERM SIGINT

# ------------------------------------------------------------
# Launch (PID1 = java)
# ------------------------------------------------------------
log INFO "Launching Minecraft (PID1)"

exec java ${JVM_ARGS} -jar server.jar ${MC_ARGS}
