#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data
SERVER_JAR="${DATA_DIR}/server.jar"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [forge] $*"
}

[[ -f "$SERVER_JAR" ]] && {
  log "server.jar already exists"
  exit 0
}

FORGE_VERSION="${FORGE_VERSION:?FORGE_VERSION required}"

log "Installing Forge ${FORGE_VERSION}"

INSTALLER="forge-${FORGE_VERSION}-installer.jar"
URL="https://maven.minecraftforge.net/net/minecraftforge/forge/${FORGE_VERSION}/${INSTALLER}"

curl -fL "$URL" -o /tmp/forge-installer.jar

java -jar /tmp/forge-installer.jar --installServer "$DATA_DIR"

mv "$DATA_DIR/forge-*-server.jar" "$SERVER_JAR"

log "Forge server.jar ready"
