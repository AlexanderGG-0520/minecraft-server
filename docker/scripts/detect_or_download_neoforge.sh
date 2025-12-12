#!/bin/bash
set -euo pipefail
log() { echo "[neoforge] $*"; }

MC_VERSION="${VERSION:?VERSION required}"
DATA_DIR="/data"
SERVER_JAR="${DATA_DIR}/server.jar"

META_URL="https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml"

LATEST=$(curl -fsSL "$META_URL" | grep "<latest>" | sed -E 's/.*<latest>(.*)<\/latest>.*/\1/')
log "Latest NeoForge version: ${LATEST}"

# match mc version (e.g. 1.21.x)
MATCH=$(echo "$LATEST" | grep "$MC_VERSION" || true)

if [[ -z "$MATCH" ]]; then
  log "No NeoForge found for ${MC_VERSION}"
  exit 1
fi

URL="https://maven.neoforged.net/releases/net/neoforged/neoforge/${LATEST}/neoforge-${LATEST}-installer.jar"
curl -fSL "$URL" -o /tmp/neoforge-installer.jar

java -jar /tmp/neoforge-installer.jar --installServer /data

FOUND=$(ls /data/neoforge-*-server.jar | head -n1)

if [[ -z "$FOUND" ]]; then
  log "Installer failed"
  exit 1
fi

mv "$FOUND" "${SERVER_JAR}"
log "NeoForge installed → ${SERVER_JAR}"
