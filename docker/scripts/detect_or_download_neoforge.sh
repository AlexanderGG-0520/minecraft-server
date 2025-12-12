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
URL="https://maven.neoforged.net/releases/net/neoforged/neoforge/${VER}/"

curl -fL "$URL" -o /neoforge-${VER}-installer.jar

java -jar /neoforge-${VER}-installer.jar --installServer "$DATA_DIR"

mv "$DATA_DIR/neoforge-*-server.jar" "$SERVER_JAR"

log "Forge server.jar ready"
