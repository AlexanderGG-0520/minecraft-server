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
READY_FILE="${DATA_DIR}/.server-ready"
RESET_FLAG="${DATA_DIR}/reset-world.flag"
LOG_FILE="${DATA_DIR}/logs/latest.log"

WORLD_NAME="${WORLD_NAME:-world}"

# ============================================================
# Env defaults (減らさない)
# ============================================================
: "${EULA:=false}"
: "${SERVER_PORT:=25569}"
: "${ONLINE_MODE:=true}"

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

mkdir -p "${DATA_DIR}/logs" "${XDG_CACHE_HOME}" "${DATA_DIR}/.nv"

rm -f "${READY_FILE}"

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
maybe_reset_world() {
  if [[ "${HARDCORE}" != "true" ]]; then
    return
  fi

  if [[ "${RESET_WORLD_ON_DEATH}" != "true" ]]; then
    return
  fi

  if [[ ! -f "${RESET_FLAG}" ]]; then
    return
  fi

  if [[ "${RESET_WORLD_CONFIRM}" != "true" ]]; then
    die "reset-world.flag present but RESET_WORLD_CONFIRM!=true (safety stop)"
  fi

  log WARN "Hardcore world reset triggered"

  for w in \
    "${DATA_DIR}/${WORLD_NAME}" \
    "${DATA_DIR}/${WORLD_NAME}_nether" \
    "${DATA_DIR}/${WORLD_NAME}_the_end"
  do
    if [[ -d "$w" ]]; then
      log WARN "Removing world directory: $w"
      rm -rf "$w"
    fi
  done

  rm -f "${RESET_FLAG}"
  log INFO "World reset completed"
}

maybe_reset_world

# ============================================================
# server.properties
# ============================================================
if [[ ! -f "${DATA_DIR}/server.properties" ]]; then
  cat > "${DATA_DIR}/server.properties" <<EOF
server-port=${SERVER_PORT}
online-mode=${ONLINE_MODE}
hardcore=${HARDCORE}
EOF
fi

# ============================================================
# JVM / MC args
# ============================================================
JVM_ARGS="$(grep -v '^\s*#' "${DATA_DIR}/jvm.args" 2>/dev/null | xargs || true)"
MC_ARGS="$(grep -v '^\s*#' "${DATA_DIR}/mc.args" 2>/dev/null | xargs || true)"

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
# Shutdown (RCON)
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
log INFO "Launching Minecraft server (hardcore=${HARDCORE})"

if [[ -f "${DATA_DIR}/fabric-server-launch.jar" ]]; then
  exec java ${JVM_ARGS} -jar "${DATA_DIR}/fabric-server-launch.jar" ${MC_ARGS}
elif [[ -f "${DATA_DIR}/server.jar" ]]; then
  exec java ${JVM_ARGS} -jar "${DATA_DIR}/server.jar" ${MC_ARGS}
else
  die "No server jar found"
fi
