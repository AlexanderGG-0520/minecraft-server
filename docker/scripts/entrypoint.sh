#!/usr/bin/env bash
set -euo pipefail

fatal() { log ERROR "$1"; exit 1; }

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$1] $2"
}

if [[ "${MC_ACCELERATION:-none}" != "opencl" ]]; then
  rm -f /data/mods/c2me-opts-accel-opencl*.jar || true
  log INFO "OpenCL acceleration disabled (c2me OpenCL module removed)"
else
  log INFO "OpenCL acceleration enabled"
fi



# ============================================================
# Load defaults
# ============================================================
log INFO "Loading base.env (defaults)"
source /opt/mc/base/base.env

TYPE_LOWER="$(echo "${TYPE}" | tr '[:upper:]' '[:lower:]')"

log START "Minecraft Runtime Booting..."
log INFO "TYPE=${TYPE_LOWER}, VERSION=${VERSION}"
log INFO "Java: $(java -version 2>&1 | head -n1)"

# itzg 互換（あれば上書き）
if [[ -f /opt/mc/base/env_compat_itzg.sh ]]; then
  source /opt/mc/base/env_compat_itzg.sh
fi

# ============================================================
# Reset world (optional)
# ============================================================
if [[ -f /data/reset-world.flag ]]; then
  log WARN "World reset triggered"
  /opt/mc/scripts/reset_world.sh
  rm -f /data/reset-world.flag
fi

# ============================================================
# TYPE layer
# ============================================================
TYPE_DIR="/opt/mc/${TYPE_LOWER}"
[[ -d "$TYPE_DIR" ]] || fatal "Missing TYPE directory: ${TYPE_DIR}"

cp -r "$TYPE_DIR"/. /data || true

# ============================================================
# Download server.jar
# ============================================================

/opt/mc/scripts/detect_or_download_${TYPE_LOWER}.sh

# ============================================================
# Build JVM / MC args
# ============================================================
/opt/mc/base/make_args.sh

# ============================================================
# EULA handling (MUST be before server launch)
# ============================================================

if [[ "${EULA:-false}" == "true" ]]; then
  echo "eula=true" > /data/eula.txt
  log INFO "EULA accepted (eula.txt written)"
else
  log WARN "EULA not accepted. Set EULA=true to run the server."
fi

# ============================================================
# Launching Minecraft Server
# ============================================================
log START "Launching Minecraft Server"

cd /data

export MC_WORKDIR=/data
export FABRIC_CACHE_DIR=/data/.fabric
export JAVA_TOOL_OPTIONS="-Duser.dir=/data"

JVM_ARGS="$(cat /data/jvm.args)"
MC_ARGS="$(cat /data/mc.args)"

# ------------------------------------------------------------
# Universal server launcher detection
# ------------------------------------------------------------

if [[ -f "/data/fabric-server-launch.jar" ]]; then
  log INFO "Detected Fabric server"
  exec java -Dfabric.gameJarPath=/data/server.jar ${JVM_ARGS} -jar /data/fabric-server-launch.jar ${MC_ARGS}


elif [[ -f "/data/quilt-server-launch.jar" ]]; then
  log INFO "Detected Quilt server"
  exec java ${JVM_ARGS} -jar /data/quilt-server-launch.jar ${MC_ARGS}

elif ls /data/forge-*-server.jar >/dev/null 2>&1; then
  FORGE_JAR=$(ls /data/forge-*-server.jar | head -n1)
  log INFO "Detected Forge server: ${FORGE_JAR}"
  exec java ${JVM_ARGS} -jar "${FORGE_JAR}" ${MC_ARGS}

elif [[ -f "/data/run.sh" ]]; then
  log INFO "Detected Forge run.sh"
  chmod +x /data/run.sh
  exec /data/run.sh

elif [[ -f "/data/server.jar" ]]; then
  log INFO "Detected Vanilla/Paper server"
  exec java ${JVM_ARGS} -jar /data/server.jar ${MC_ARGS}

else
  fatal "No supported Minecraft server launcher found in /data"
fi
