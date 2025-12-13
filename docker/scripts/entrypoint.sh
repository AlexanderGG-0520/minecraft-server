#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Logging helpers
# ============================================================
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] [$1] $2"; }
die() { log ERROR "$1"; exit 1; }

# ============================================================
# Paths
# ============================================================
DATA_DIR="${DATA_DIR:-/data}"
LOG_DIR="${DATA_DIR}/logs"
LOG_FILE="${LOG_DIR}/latest.log"
READY_FILE="${DATA_DIR}/.ready"

mkdir -p "${LOG_DIR}"
rm -f "${READY_FILE}"

# ============================================================
# Env defaults (itzg互換寄り / 透明性重視)
# ============================================================
: "${EULA:=false}"
: "${TYPE:=auto}"        # auto|fabric|neoforge|forge|paper|vanilla
: "${VERSION:=}"         # optional (表示用)
: "${AUTO_INSTALL:=false}"  # ★ legacy: 何もしない（削除予定）

: "${ENABLE_RCON:=false}"
: "${RCON_PORT:=25575}"
: "${RCON_PASSWORD:=changeme}"
: "${STOP_SERVER_ANNOUNCE_DELAY:=10}"

# ============================================================
# Cache dirs (GPU / C2ME / OpenCL)
# ============================================================
export HOME="${DATA_DIR}"
export XDG_CACHE_HOME="${DATA_DIR}/.cache"
export CUDA_CACHE_PATH="${DATA_DIR}/.nv/ComputeCache"

mkdir -p "${XDG_CACHE_HOME}" "${DATA_DIR}/.nv"

log INFO "Cache configuration"
log INFO "  XDG_CACHE_HOME=${XDG_CACHE_HOME}"
log INFO "  CUDA_CACHE_PATH=${CUDA_CACHE_PATH}"

# ============================================================
# EULA
# ============================================================
if [[ "${EULA}" == "true" ]]; then
  echo "eula=true" > "${DATA_DIR}/eula.txt"
  log INFO "EULA accepted via env"
else
  [[ -f "${DATA_DIR}/eula.txt" ]] || die "EULA not accepted (set EULA=true)"
fi

# ============================================================
# JVM / MC args (完全透過)
# ============================================================
JVM_ARGS="$(grep -v '^\s*#' "${DATA_DIR}/jvm.args" 2>/dev/null | xargs || true)"
MC_ARGS="$(grep -v '^\s*#' "${DATA_DIR}/mc.args" 2>/dev/null | xargs || true)"

log INFO "JVM_ARGS=${JVM_ARGS:-<empty>}"
log INFO "MC_ARGS=${MC_ARGS:-<empty>}"

# ============================================================
# Server binary detection (NO auto-install)
# ============================================================
SERVER_KIND=""
SERVER_JAR=""

if [[ -f "${DATA_DIR}/fabric-server-launch.jar" ]]; then
  SERVER_KIND="fabric"
  SERVER_JAR="${DATA_DIR}/fabric-server-launch.jar"

elif [[ -f "${DATA_DIR}/quilt-server-launch.jar" ]]; then
  SERVER_KIND="quilt"
  SERVER_JAR="${DATA_DIR}/quilt-server-launch.jar"

elif ls "${DATA_DIR}"/neoforge-*-server.jar >/dev/null 2>&1; then
  SERVER_KIND="neoforge"
  SERVER_JAR="$(ls ${DATA_DIR}/neoforge-*-server.jar | head -n1)"

elif ls "${DATA_DIR}"/forge-*-server.jar >/dev/null 2>&1; then
  SERVER_KIND="forge"
  SERVER_JAR="$(ls ${DATA_DIR}/forge-*-server.jar | head -n1)"

elif [[ -f "${DATA_DIR}/paper.jar" ]]; then
  SERVER_KIND="paper"
  SERVER_JAR="${DATA_DIR}/paper.jar"

elif [[ -f "${DATA_DIR}/server.jar" ]]; then
  SERVER_KIND="vanilla"
  SERVER_JAR="${DATA_DIR}/server.jar"
fi

log INFO "Detected server kind: ${SERVER_KIND:-none}"

# ============================================================
# Hard fail if missing (ここが最重要)
# ============================================================
if [[ -z "${SERVER_KIND}" ]]; then
  log ERROR "No supported server binary found in ${DATA_DIR}"
  log ERROR "AUTO_INSTALL is disabled by design"
  log ERROR "Expected one of:"
  log ERROR "  - fabric-server-launch.jar"
  log ERROR "  - quilt-server-launch.jar"
  log ERROR "  - neoforge-*-server.jar"
  log ERROR "  - forge-*-server.jar"
  log ERROR "  - paper.jar"
  log ERROR "  - server.jar"
  exit 1
fi

# ============================================================
# Readiness watcher (log-based)
# ============================================================
readiness_watcher() {
  until [[ -f "${LOG_FILE}" ]]; do sleep 1; done
  tail -Fn0 "${LOG_FILE}" | while read -r line; do
    if echo "$line" | grep -q 'Done (.*)! For help, type "help"'; then
      touch "${READY_FILE}"
      log INFO "Server READY"
      break
    fi
  done
}
readiness_watcher &

# ============================================================
# Graceful shutdown (RCON)
# ============================================================
shutdown() {
  log INFO "Shutdown requested"
  if [[ "${ENABLE_RCON}" == "true" ]]; then
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
# Launch
# ============================================================
log INFO "Launching Minecraft server"
log INFO "  KIND=${SERVER_KIND}"
log INFO "  JAR=${SERVER_JAR}"

exec java ${JVM_ARGS} -jar "${SERVER_JAR}" ${MC_ARGS}
