#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# 🧠 Common
# ============================================================

LOG_PREFIX="[MC-ENTRYPOINT]"
log() {
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ${LOG_PREFIX} [$1] $2"
}

fatal() {
  log FATAL "$1"
  exit 1
}

# ============================================================
# 📁 Paths
# ============================================================

DATA_DIR="/data"
READY_FILE="${DATA_DIR}/ready"
STARTED_FILE="${DATA_DIR}/started"

JVM_ARGS_FILE="${DATA_DIR}/jvm.args"
MC_ARGS_FILE="${DATA_DIR}/mc.args"
SERVER_PROPERTIES="${DATA_DIR}/server.properties"

# ============================================================
# 🌍 Defaults（envを減らさない思想）
# ============================================================

: "${EULA:=false}"
: "${TYPE:=fabric}"
: "${VERSION:=latest}"
: "${JAVA_VERSION:=25}"

: "${SERVER_PORT:=25565}"
: "${ENABLE_GUI:=false}"

: "${MAX_MEMORY:=2G}"
: "${MIN_MEMORY:=${MAX_MEMORY}}"

: "${ENABLE_OPENCL:=false}"
: "${MC_ACCELERATION:=none}"
: "${C2ME_ENABLED:=false}"

: "${ENABLE_RCON:=false}"
: "${RCON_PORT:=25575}"
: "${RCON_PASSWORD:=}"

: "${STOP_SERVER_ANNOUNCE_DELAY:=30}"
: "${STOP_SERVER_MESSAGE:=Server shutting down in 30 seconds}"

: "${LOG_LEVEL:=INFO}"
: "${DEBUG:=false}"

# ============================================================
# 📜 EULA
# ============================================================

if [[ "${EULA}" != "true" ]]; then
  fatal "You must accept the EULA by setting EULA=true"
fi

log INFO "EULA accepted via env (EULA=true)"

echo "eula=true" > "${DATA_DIR}/eula.txt"

# ============================================================
# ⚙️ JVM args
# ============================================================

if [[ ! -f "${JVM_ARGS_FILE}" ]]; then
  log INFO "Generating default jvm.args"

  cat > "${JVM_ARGS_FILE}" <<EOF
-Xms${MIN_MEMORY}
-Xmx${MAX_MEMORY}

-XX:+UseG1GC
-XX:+ParallelRefProcEnabled
-XX:MaxGCPauseMillis=200

-Dfile.encoding=UTF-8
-Dsun.stdout.encoding=UTF-8
-Dsun.stderr.encoding=UTF-8
EOF
fi

JVM_ARGS="$(grep -v '^\s*#' "${JVM_ARGS_FILE}" | grep -v '^\s*$' | xargs)"

# ============================================================
# ⚙️ MC args
# ============================================================

if [[ ! -f "${MC_ARGS_FILE}" ]]; then
  log INFO "Generating default mc.args"
  echo "nogui" > "${MC_ARGS_FILE}"
fi

MC_ARGS="$(grep -v '^\s*#' "${MC_ARGS_FILE}" | grep -v '^\s*$' | xargs)"

# ============================================================
# 🧾 server.properties
# ============================================================

log INFO "Rendering server.properties"

cat > "${SERVER_PROPERTIES}" <<EOF
server-port=${SERVER_PORT}
enable-rcon=${ENABLE_RCON}
rcon.port=${RCON_PORT}
rcon.password=${RCON_PASSWORD}
online-mode=${ONLINE_MODE:-true}
difficulty=${DIFFICULTY:-normal}
view-distance=${VIEW_DISTANCE:-10}
simulation-distance=${SIMULATION_DISTANCE:-10}
enable-command-block=${ENABLE_COMMAND_BLOCK:-false}
spawn-protection=${SPAWN_PROTECTION:-0}
EOF

# ============================================================
# 🗑️ Reset World
# ============================================================
if [[ "${RESET_WORLD_FLAG:-false}" == "true" ]]; then
  log INFO "RESET_WORLD is true, resetting world data..."
  /opt/mc/scripts/reset_world.sh
  rm -f "${RESET_WORLD_FLAG}"
  log INFO "World reset completed."
fi

# ============================================================
# 🚦 Graceful Shutdown (RCON)
# ============================================================

graceful_shutdown() {
  log INFO "Received termination signal"

  if [[ "${ENABLE_RCON}" == "true" && -n "${RCON_PASSWORD}" ]]; then
    log INFO "Sending RCON shutdown announcement"

    echo "say ${STOP_SERVER_MESSAGE}" | \
      timeout 5 mc-rcon -H 127.0.0.1 -P "${RCON_PORT}" -p "${RCON_PASSWORD}" || true

    sleep "${STOP_SERVER_ANNOUNCE_DELAY}"

    echo "stop" | \
      timeout 5 mc-rcon -H 127.0.0.1 -P "${RCON_PORT}" -p "${RCON_PASSWORD}" || true
  fi

  log INFO "Shutdown sequence completed"
  exit 0
}

trap graceful_shutdown SIGTERM SIGINT

# ============================================================
# 🧠 Acceleration info
# ============================================================

if [[ "${ENABLE_OPENCL}" == "true" ]]; then
  log INFO "OpenCL acceleration enabled"
fi

if [[ "${C2ME_ENABLED}" == "true" ]]; then
  log INFO "C2ME optimizations enabled"
fi

# ============================================================
# 🚀 Server launcher detection
# ============================================================

touch "${STARTED_FILE}"
log INFO "Minecraft Runtime Booting..."

if [[ -f "${DATA_DIR}/fabric-server-launch.jar" ]]; then
  log INFO "Detected Fabric server"
  exec java \
    ${JVM_ARGS} \
    -Dfabric.gameJarPath="${DATA_DIR}/server.jar" \
    -jar "${DATA_DIR}/fabric-server-launch.jar" \
    ${MC_ARGS}

elif [[ -f "${DATA_DIR}/quilt-server-launch.jar" ]]; then
  log INFO "Detected Quilt server"
  exec java ${JVM_ARGS} -jar "${DATA_DIR}/quilt-server-launch.jar" ${MC_ARGS}

elif ls "${DATA_DIR}"/forge-*-server.jar >/dev/null 2>&1; then
  FORGE_JAR="$(ls "${DATA_DIR}"/forge-*-server.jar | head -n1)"
  log INFO "Detected Forge server: ${FORGE_JAR}"
  exec java ${JVM_ARGS} -jar "${FORGE_JAR}" ${MC_ARGS}

elif [[ -f "${DATA_DIR}/run.sh" ]]; then
  log INFO "Detected Forge run.sh"
  chmod +x "${DATA_DIR}/run.sh"
  exec "${DATA_DIR}/run.sh"

elif [[ -f "${DATA_DIR}/server.jar" ]]; then
  log INFO "Detected Vanilla/Paper server"
  exec java ${JVM_ARGS} -jar "${DATA_DIR}/server.jar" ${MC_ARGS}

else
  fatal "No supported Minecraft server launcher found in /data"
fi
