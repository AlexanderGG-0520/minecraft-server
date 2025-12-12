#!/bin/bash
set -euo pipefail
log() { echo "[fabric] $*"; }

MC_VERSION="${VERSION:?VERSION required}"
LOADER="${FABRIC_LOADER:-latest}"
DATA_DIR="/data"
SERVER_JAR="${DATA_DIR}/server.jar"

# 1. Resolve loader version
if [[ "$LOADER" == "latest" ]]; then
  LOADER=$(curl -fsSL "https://meta.fabricmc.net/v2/versions/loader" | jq -r '.[0].version')
fi

log "Fabric loader=${LOADER}"

# 2. Resolve installer
INSTALLER=$(curl -fsSL "https://meta.fabricmc.net/v2/versions/installer" | jq -r '.[0].version')
log "installer=${INSTALLER}"

# 3. Resolve profile json
PROFILE_URL="https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${LOADER}/profile/json"
log "download profile: ${PROFILE_URL}"

curl -fsSL "$PROFILE_URL" -o "/tmp/profile.json"

# 4. extract server.jar URL
URL=$(jq -r '.server.url' /tmp/profile.json)
log "server jar = $URL"

curl -fSL "$URL" -o "${SERVER_JAR}.tmp"
mv "${SERVER_JAR}.tmp" "${SERVER_JAR}"
log "Fabric server installed"
