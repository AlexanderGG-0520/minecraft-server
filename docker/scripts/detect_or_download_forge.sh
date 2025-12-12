#!/bin/bash
set -euo pipefail
log() { echo "[forge] $*"; }

MC_VERSION="${VERSION:?VERSION required}"
DATA_DIR="/data"
SERVER_JAR="${DATA_DIR}/server.jar"

# 1. Resolve recommended forge version
FORGE_VERSION=$(curl -fsSL "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json" \
  | jq -r --arg v "$MC_VERSION" '.promos[$v + "-recommended"]')

if [[ "$FORGE_VERSION" == "null" ]]; then
  log "Forge does not support version ${MC_VERSION}"
  exit 1
fi

log "Forge version=${FORGE_VERSION}"

# 2. Download installer
URL="https://maven.minecraftforge.net/net/minecraftforge/forge/${FORGE_VERSION}/forge-${FORGE_VERSION}-installer.jar"
log "Installer: $URL"

curl -fSL "$URL" -o /tmp/forge-installer.jar

# 3. Run installer (server)
java -jar /tmp/forge-installer.jar --installServer /data

# 4. Detect server jar
FOUND=$(ls /data/forge-*-server.jar | head -n1)

if [[ -z "$FOUND" ]]; then
  log "ERROR: Forge installer failed"
  exit 1
fi

mv "$FOUND" "${SERVER_JAR}"
log "Forge server installed → ${SERVER_JAR}"
