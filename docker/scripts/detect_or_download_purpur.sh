#!/bin/bash
set -euo pipefail

log() { echo "[purpur] $*"; }

MC_VERSION="${VERSION:?VERSION required}"
PURPUR_BUILD="${PURPUR_BUILD:-latest}"
DATA_DIR="/data"
SERVER_JAR="${DATA_DIR}/server.jar"

log "Purpur resolver started (MC=${MC_VERSION}, requested build=${PURPUR_BUILD})"

# ----------------------------------------------------------
# 1. Check version exists
# ----------------------------------------------------------
VERSION_API="https://api.purpurmc.org/v2/purpur"

if ! curl -fsSL "${VERSION_API}" | jq -e --arg v "$MC_VERSION" '.versions | index($v)' >/dev/null; then
  log "ERROR: Purpur does not support MC version ${MC_VERSION}"
  exit 1
fi

# ----------------------------------------------------------
# 2. Resolve build number
# ----------------------------------------------------------
if [[ "$PURPUR_BUILD" == "latest" ]]; then
  BUILD=$(curl -fsSL "https://api.purpurmc.org/v2/purpur/${MC_VERSION}/latest" | jq -r '.build')
  log "Resolved latest Purpur build: ${BUILD}"
else
  BUILD="$PURPUR_BUILD"
  log "Using user-specified Purpur build: ${BUILD}"
fi

# ----------------------------------------------------------
# 3. Download Purpur jar
# ----------------------------------------------------------
DOWNLOAD_URL="https://api.purpurmc.org/v2/purpur/${MC_VERSION}/${BUILD}/download"

log "Downloading Purpur from: ${DOWNLOAD_URL}"

curl -fSL "${DOWNLOAD_URL}" -o "${SERVER_JAR}.tmp" || {
  log "ERROR: Failed to download Purpur"
  exit 1
}

mv "${SERVER_JAR}.tmp" "${SERVER_JAR}"

log "Purpur server installed successfully → ${SERVER_JAR}"
