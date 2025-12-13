#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Logging
# ============================================================
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] [$1] $2"; }
die() { log ERROR "$1"; exit 1; }

# ============================================================
# Paths
# ============================================================
DATA_DIR="${DATA_DIR:-/data}"
LOG_FILE="${DATA_DIR}/logs/latest.log"
READY_FILE="${DATA_DIR}/.ready"
RESET_FLAG="${DATA_DIR}/reset-world.flag"

WORLD_NAME="${WORLD_NAME:-world}"

mkdir -p "${DATA_DIR}/logs"
rm -f "${READY_FILE}"

# ============================================================
# Env defaults（減らさない）
# ============================================================
: "${EULA:=false}"
: "${HARDCORE:=false}"
: "${RESET_WORLD_ON_DEATH:=false}"
: "${RESET_WORLD_CONFIRM:=false}"

: "${ENABLE_RCON:=false}"
: "${RCON_PORT:=25575}"
: "${RCON_PASSWORD:=changeme}"
: "${STOP_SERVER_ANNOUNCE_DELAY:=10}"

# ============================================================
# Cache dirs (C2ME / OpenCL 永続)
# ============================================================
export HOME="${DATA_DIR}"
export XDG_CACHE_HOME="${DATA_DIR}/.cache"
export CUDA_CACHE_PATH="${DATA_DIR}/.nv/ComputeCache"
export CUDA_CACHE_MAXSIZE="${CUDA_CACHE_MAXSIZE:-2147483648}"

mkdir -p "${XDG_CACHE_HOME}" "${DATA_DIR}/.nv"

# ============================================================
# EULA
# ============================================================
if [[ "${EULA}" == "true" ]]; then
  echo "eula=true" > "${DATA_DIR}/eula.txt"
  log INFO "EULA accepted via env"
else
  [[ -f "${DATA_DIR}/eula.txt" ]] || die "EULA not accepted"
fi

# ============================================================
# Hardcore World Reset
# ============================================================
if [[ "${HARDCORE}" == "true" && "${RESET_WORLD_ON_DEATH}" == "true" && -f "${RESET_FLAG}" ]]; then
  [[ "${RESET_WORLD_CONFIRM}" == "true" ]] || die "RESET_WORLD_CONFIRM!=true (safety stop)"

  log WARN "Hardcore world reset triggered"
  rm -rf \
    "${DATA_DIR}/${WORLD_NAME}" \
    "${DATA_DIR}/${WORLD_NAME}_nether" \
    "${DATA_DIR}/${WORLD_NAME}_the_end" || true

  rm -f "${RESET_FLAG}"
  log INFO "World reset completed"
fi

# ============================================================
# JVM / MC args
# ============================================================
JVM_ARGS="$(grep -v '^\s*#' "${DATA_DIR}/jvm.args" 2>/dev/null | xargs || true)"
MC_ARGS="$(grep -v '^\s*#' "${DATA_DIR}/mc.args" 2>/dev/null | xargs || true)"

# ============================================================
# Readiness watcher（log-based）
# ============================================================
(
  until [[ -f "${LOG_FILE}" ]]; do sleep 1; done
  tail -Fn0 "${LOG_FILE}" | while read -r line; do
    if echo "$line" | grep -q 'Done (.*)! For help, type "help"'; then
      touch "${READY_FILE}"
      log INFO "Server READY"
      break
    fi
  done
) &

# ============================================================
# Graceful shutdown (PID1)
# ============================================================
shutdown() {
  log INFO "Shutdown requested"
  if [[ "${ENABLE_RCON}" == "true" ]] && command -v rcon-cli >/dev/null 2>&1; then
    echo "say Server shutting down in ${STOP_SERVER_ANNOUNCE_DELAY}s" | \
      timeout 3 rcon-cli --host 127.0.0.1 --port "${RCON_PORT}" --password "${RCON_PASSWORD}" || true
    sleep "${STOP_SERVER_ANNOUNCE_DELAY}"
    echo "stop" | \
      timeout 3 rcon-cli --host 127.0.0.1 --port "${RCON_PORT}" --password "${RCON_PASSWORD}" || true
  fi
  exit 0
}
trap shutdown SIGTERM SIGINT

# ============================================================
# Launch（ここが最重要：exec）
# ============================================================
log INFO "Launching Minecraft (PID1)"

if [[ -f "${DATA_DIR}/fabric-server-launch.jar" ]]; then
  exec java ${JVM_ARGS} -jar "${DATA_DIR}/fabric-server-launch.jar" ${MC_ARGS}
elif [[ -f "${DATA_DIR}/server.jar" ]]; then
  exec java ${JVM_ARGS} -jar "${DATA_DIR}/server.jar" ${MC_ARGS}
else
  die "No server jar found"
fi
