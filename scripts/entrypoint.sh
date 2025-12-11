#!/usr/bin/env bash
set -euo pipefail

echo "=== alexandergg-0520/minecraft-server (entrypoint) ==="
echo "User: $(whoami)"
echo "Java version:"
java -version || true
echo "---------------------------------------------"

# ============================================================================
# 1. Environment defaults
# ============================================================================
TYPE="${TYPE:-fabric}"              # fabric | paper | neoforge
VERSION="${VERSION:-latest}"        # Minecraft version
MEMORY="${MEMORY:-4G}"              # Xms/Xmx
LOG_FORMAT="${LOG_FORMAT:-plain}"   # plain | json
CRASH_TIMEOUT="${CRASH_TIMEOUT:-5}" # prevent K8s crash loops
ENABLE_RCON="${ENABLE_RCON:-false}"

# Ensure /data exists
mkdir -p /data
chown -R mc:mc /data || true

# ============================================================================
# 2. EULA Check
# ============================================================================
if [[ "${EULA:-false}" != "true" ]]; then
  echo "[ERROR] You must accept the EULA by setting EULA=true"
  sleep "${CRASH_TIMEOUT}"
  exit 1
fi

# ============================================================================
# 3. World Reset Logic
# ============================================================================
if [[ -f "/data/reset-world.flag" ]] || [[ "${WORLD_RESET_POLICY:-never}" == "always_on_start" ]]; then
  echo "[INFO] Resetting world…"
  /opt/mc/reset_world.sh
fi

# ============================================================================
# 4. S3 / MinIO Mod Sync
# ============================================================================
if [[ "${MODS_SOURCE:-}" == "s3" ]]; then
  echo "[INFO] Syncing mods/config using MinIO client"
  /opt/mc/sync_s3.sh
fi

# ============================================================================
# 5. Load base environment and files
# ============================================================================
if [ -f /opt/mc/base/base.env ]; then
  log "Loading base environment defaults"
  set -a
  . /opt/mc/base/base.env
  set +a
fi

# Copy base files into /data if not present
log "Applying base configuration"
cp -n /opt/mc/base/server.properties /data/ || true
cp -n /opt/mc/base/whitelist.json /data/ || true
cp -n /opt/mc/base/ops.json /data/ || true

# Load common JVM flags
if [ -f /opt/mc/base/jvm-common.args ]; then
  BASE_JVM_FLAGS="$(cat /opt/mc/base/jvm-common.args | tr '\n' ' ')"
  JAVA_ARGS="${JAVA_ARGS:-${BASE_JVM_FLAGS}}"
fi

# ============================================================
# 6. Apply TYPE-specific configuration layer
# ============================================================

TYPE_DIR="/opt/mc/${TYPE}"

if [ -d "${TYPE_DIR}" ]; then
    log "Applying TYPE-specific config for TYPE=${TYPE}"

    # 1) Copy config files (*.yml, *.toml, *.properties, etc)
    find "${TYPE_DIR}" -maxdepth 1 -type f ! -name "*.args" | while read file; do
        filename=$(basename "$file")
        if [ ! -f "/data/${filename}" ]; then
            log " - copying $filename"
            cp "$file" "/data/$filename"
        else
            log " - keeping existing $filename (user override)"
        fi
    done

    # 2) Merge JVM args
    if [ -f "${TYPE_DIR}/jvm.args" ]; then
        log "Merging TYPE-specific jvm.args"
        TYPE_JVM_ARGS="$(cat ${TYPE_DIR}/jvm.args | tr '\n' ' ')"
        JAVA_FLAGS="${JAVA_FLAGS} ${TYPE_JVM_ARGS}"
    fi

    # 3) Merge MC args
    if [ -f "${TYPE_DIR}/mc.args" ]; then
        log "Merging TYPE-specific mc.args"
        if [ ! -f /data/mc.args ]; then
            cp "${TYPE_DIR}/mc.args" /data/mc.args
        else
            cat "${TYPE_DIR}/mc.args" >> /data/mc.args
        fi
    fi

else
    log "No TYPE-specific directory found for TYPE=${TYPE}"
fi

# ============================================================================
# 7. Detect or download server.jar
# ============================================================================
if [[ ! -f "/data/server.jar" ]]; then
  echo "[INFO] No server.jar found. Installing TYPE=${TYPE}, VERSION=${VERSION}"
  /opt/mc/detect_or_download_server.sh "${TYPE}" "${VERSION}"
else
  echo "[INFO] server.jar already exists. Skipping installation."
fi

# ============================================================================
# 8. Logging Format
# ============================================================================
if [[ "${LOG_FORMAT}" == "json" ]]; then
  echo "[INFO] JSON logging enabled"
  # NOTE: Real JSON logging requires log4j config. This flag prevents lookup vuln.
  JVM_LOGGING_FLAGS="-Dlog4j2.formatMsgNoLookups=true"
else
  JVM_LOGGING_FLAGS=""
fi

# ============================================================================
# 9. JVM ARGS (C2ME / Java25 向け最適化)
# ============================================================================
DEFAULT_JVM_FLAGS="
  -Xms${MEMORY}
  -Xmx${MEMORY}
  -XX:+UseG1GC
  -XX:+UnlockExperimentalVMOptions
  -XX:+EnableJVMCI
"

# Java 25 では Panama / Vector API 利用が想定されるため対応
if java -version 2>&1 | grep -q "25"; then
  echo "[INFO] Java 25 detected — enabling Panama & Vector optimizations"
  DEFAULT_JVM_FLAGS+="
    --add-modules=jdk.incubator.vector
    --enable-native-access=ALL-UNNAMED
  "
fi

JAVA_ARGS="${JAVA_ARGS:-$DEFAULT_JVM_FLAGS}"

# ============================================================================
# 10. RCON
# ============================================================================
if [[ "${ENABLE_RCON}" == "true" ]]; then
  echo "[INFO] RCON enabled"
else
  echo "[INFO] RCON disabled"
fi

# ============================================================
# 11. Final JVM flag assembly
# ============================================================

# Base flags
if [ -f /opt/mc/base/jvm-common.args ]; then
  COMMON_JVM_ARGS="$(cat /opt/mc/base/jvm-common.args | tr '\n' ' ')"
  JAVA_FLAGS="${COMMON_JVM_ARGS} ${JAVA_FLAGS}"
fi

# User overrides (/data/jvm.args)
if [ -f /data/jvm.args ]; then
  USER_JVM_ARGS="$(cat /data/jvm.args | tr '\n' ' ')"
  JAVA_FLAGS="${JAVA_FLAGS} ${USER_JVM_ARGS}"
fi

log "Final JVM flags:"
log "${JAVA_FLAGS}"

# ============================================================================
# 12. Start the Minecraft server
# ============================================================================
MC_ARGS="${MC_ARGS:-nogui}"

echo "---------------------------------------------"
echo "Starting Minecraft server:"
echo "  TYPE    = ${TYPE}"
echo "  VERSION = ${VERSION}"
echo "  MEMORY  = ${MEMORY}"
echo "  JAVA    = $(java -version 2>&1 | head -n 1)"
echo "  LOGGING = ${LOG_FORMAT}"
echo "---------------------------------------------"

cd /data

exec java ${JAVA_ARGS} ${JVM_LOGGING_FLAGS} -jar /data/server.jar ${MC_ARGS}
