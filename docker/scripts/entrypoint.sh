#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Utilities
# ============================================================

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$1] $2"
}

fatal() {
  log FATAL "$1"
  exit 1
}

# ============================================================
# Paths
# ============================================================

DATA_DIR="/data"
MC_DIR="/opt/mc"
SCRIPTS_DIR="${MC_DIR}/scripts"
BASE_DIR="${MC_DIR}/base"

EULA_FILE="${DATA_DIR}/eula.txt"
JVM_ARGS_FILE="${DATA_DIR}/jvm.args"
MC_ARGS_FILE="${DATA_DIR}/mc.args"
SERVER_PROPERTIES="${DATA_DIR}/server.properties"

# ============================================================
# Defaults (safe)
# ============================================================

: "${EULA:=false}"
: "${ENABLE_GUI:=false}"
: "${STOP_SERVER_ANNOUNCE_DELAY:=0}"

# ============================================================
# 1. EULA handling (pre-generate)
# ============================================================

if [[ "${EULA}" == "true" ]]; then
  echo "eula=true" > "${EULA_FILE}"
  log INFO "EULA accepted via env (EULA=true)"
else
  [[ -f "${EULA_FILE}" ]] || fatal "EULA is not accepted. Set EULA=true"
fi

# ============================================================
# 2. Load base.env (defaults)
# ============================================================

log INFO "Checking for empty variables and applying default values"

if [[ -f "${BASE_DIR}/base.env" ]]; then
  log INFO "Loading base.env (defaults)"
  set -a
  source "${BASE_DIR}/base.env"
  set +a
fi

# ============================================================
# 3. Generate jvm.args (only once)
# ============================================================

if [[ ! -f "${JVM_ARGS_FILE}" ]]; then
  log INFO "Generating jvm.args"
  cat > "${JVM_ARGS_FILE}" <<EOF
-Xms${MIN_MEMORY:-2G}
-Xmx${MAX_MEMORY:-2G}

-Dfile.encoding=UTF-8
-Dsun.stdout.encoding=UTF-8
-Dsun.stderr.encoding=UTF-8

-XX:+UseG1GC
-XX:+ParallelRefProcEnabled
-XX:MaxGCPauseMillis=200
EOF
else
  log INFO "jvm.args already exists, skipping auto-generation"
fi

# ============================================================
# 4. Generate mc.args (NO PORT HERE)
# ============================================================

if [[ ! -f "${MC_ARGS_FILE}" ]]; then
  log INFO "Generating mc.args"
  touch "${MC_ARGS_FILE}"
  if [[ "${ENABLE_GUI}" == "false" ]]; then
    echo "nogui" >> "${MC_ARGS_FILE}"
  fi
fi

# ============================================================
# 5. server.properties render
# ============================================================

if [[ ! -f "${SERVER_PROPERTIES}" ]]; then
  log INFO "Rendering server.properties from environment variables"
  envsubst < "${BASE_DIR}/server.properties.tpl" > "${SERVER_PROPERTIES}"
  log INFO "server.properties generated successfully at ${SERVER_PROPERTIES}"
fi

# ============================================================
# 6. OPS / WHITELIST
# ============================================================

if [[ -n "${OPS:-}" ]]; then
  log INFO "Applying OPS settings"
  "${SCRIPTS_DIR}/apply_ops.sh"
fi

if [[ -n "${WHITELIST:-}" ]]; then
  log INFO "Applying WHITELIST settings"
  "${SCRIPTS_DIR}/apply_whitelist.sh"
fi

# ============================================================
# 7. Optional RCON delayed STOP announce
# ============================================================

if [[ "${STOP_SERVER_ANNOUNCE_DELAY}" != "0" ]]; then
  log INFO "RCON STOP announce delay enabled (${STOP_SERVER_ANNOUNCE_DELAY}s)"
  "${SCRIPTS_DIR}/rcon_delayed_stop.sh" &
fi

# ============================================================
# 7. Reset World FLAGS (non-fatal)
# ============================================================
if [[ "${RESET_WORLD_FLAGS:-false}" == "true" ]]; then
  log INFO "Resetting world flags (non-fatal)"
  "${SCRIPTS_DIR}/reset_world.sh" || log WARN "Failed to reset world flags (non-fatal)"
  rm -f "${DATA_DIR}/RESET_WORLD_FLAGS"
fi

# ============================================================
# 8. OpenCL diagnostics (non-fatal)
# ============================================================

if [[ "${ENABLE_OPENCL:-false}" == "true" ]]; then
  log INFO "OpenCL enabled, checking devices"
  clinfo >/dev/null 2>&1 || log WARN "clinfo failed (non-fatal)"
fi

# ============================================================
# 9. Launch Minecraft (single exec)
# ============================================================

log START "Minecraft Runtime Booting..."

JVM_ARGS="$(grep -v '^\s*#' "${JVM_ARGS_FILE}" | grep -v '^\s*$' | xargs)"
MC_ARGS="$(grep -v '^\s*#' "${MC_ARGS_FILE}"  | grep -v '^\s*$' | xargs)"

if [[ -f "${DATA_DIR}/fabric-server-launch.jar" ]]; then
  log INFO "Detected Fabric server"
  exec java -Dfabric.gameJarPath=${DATA_DIR}/server.jar ${JVM_ARGS} \
    -jar ${DATA_DIR}/fabric-server-launch.jar ${MC_ARGS}

elif [[ -f "${DATA_DIR}/quilt-server-launch.jar" ]]; then
  log INFO "Detected Quilt server"
  exec java ${JVM_ARGS} -jar ${DATA_DIR}/quilt-server-launch.jar ${MC_ARGS}

elif ls ${DATA_DIR}/forge-*-server.jar >/dev/null 2>&1; then
  FORGE_JAR=$(ls ${DATA_DIR}/forge-*-server.jar | head -n1)
  log INFO "Detected Forge server: ${FORGE_JAR}"
  exec java ${JVM_ARGS} -jar "${FORGE_JAR}" ${MC_ARGS}

elif [[ -f "${DATA_DIR}/run.sh" ]]; then
  log INFO "Detected Forge run.sh"
  chmod +x ${DATA_DIR}/run.sh
  exec ${DATA_DIR}/run.sh

elif [[ -f "${DATA_DIR}/server.jar" ]]; then
  log INFO "Detected Vanilla/Paper server"
  exec java ${JVM_ARGS} -jar ${DATA_DIR}/server.jar ${MC_ARGS}

else
  fatal "No supported Minecraft server launcher found in /data"
fi
