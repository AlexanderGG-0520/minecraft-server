#!/usr/bin/env bash
set -euo pipefail

fatal() { log ERROR "$1"; exit 1; }

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$1] $2"
}

# ------------------------------------------------------------
# Check and Set Default Values for Missing Variables
# ------------------------------------------------------------
log INFO "Checking for empty variables and applying default values"

# List of critical environment variables with defaults
: "${SERVER_PORT:=25565}"
: "${RCON_PORT:=25575}"
: "${MAX_PLAYERS:=20}"
: "${SERVER_IP:=""}"
: "${ONLINE_MODE:=true}"
: "${ENABLE_RCON:=false}"
: "${RCON_PASSWORD:="change_this_password"}"
: "${RCON_MAX_CONNECTIONS:=5}"
: "${RCON_TIMEOUT:=60}"

# ------------------------------------------------------------
# Load defaults
# ------------------------------------------------------------
log INFO "Loading base.env (defaults)"
source /opt/mc/base/base.env

# ------------------------------------------------------------
# Reset world if RESET_FLAG is true
# ------------------------------------------------------------
if [[ "${RESET_FLAG:-false}" == "true" ]]; then
  log INFO "RESET_FLAG is true, resetting world data..."
  /opt/mc/scripts/reset_world.sh
  rm -f /data/RESET_FLAG
  log INFO "World data reset completed."
fi

# ------------------------------------------------------------
# YAML settings override (if any)
# ------------------------------------------------------------
log INFO "Overriding base.env with YAML values (if any)"
if [[ -f /data/server-settings.yaml ]]; then
  log INFO "Reading settings from server-settings.yaml"
  # YAML から設定を読み込んで環境変数に設定
  eval $(parse_yaml /data/server-settings.yaml)
fi

# ============================================================
# JVM & MC Arguments Generation
# ============================================================

log INFO "Generating jvm.args if missing"
/opt/mc/scripts/generate_jvm_args.sh

log INFO "Generating mc.args if missing"
/opt/mc/scripts/generate_mc_args.sh


# ------------------------------------------------------------
# Render server.properties from base.env (and overridden values)
# ------------------------------------------------------------
log INFO "Rendering server.properties from base.env and YAML"
/opt/mc/scripts/render_server_properties.sh
log INFO "server.properties generated successfully"

# ============================================================
# OPS and WHITELIST Application
# ============================================================
log INFO "Applying OPS and WHITELIST settings"
/opt/mc/scripts/apply_ops_and_whitelist.sh
log INFO "OPS and WHITELIST settings applied successfully"

# ------------------------------------------------------------
# Proceed with server start-up steps
# ------------------------------------------------------------
log START "Minecraft Runtime Booting..."

# Other operations like resetting world, downloading server jar, etc.

# Launching Minecraft Server
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

# ============================================================
# Healthcheck script
# ============================================================
log INFO "Setting up healthcheck script"

/opt/mc/scripts/scripthealthcheck.sh
