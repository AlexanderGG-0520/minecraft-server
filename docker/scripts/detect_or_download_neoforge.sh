#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [neoforge] $*"
}

# NeoForge は run.sh を生成するのが正
[[ -f "${DATA_DIR}/run.sh" ]] && {
  log "NeoForge already installed"
  exit 0
}

VERSION="${VERSION:?VERSION is required}"                 # 例: 1.21.1
NEOFORGE_VERSION="${NEOFORGE_VERSION:?NEOFORGE_VERSION is required}"  # 例: 21.1.12

log "Installing NeoForge ${VERSION}-${NEOFORGE_VERSION}"

INSTALLER="neoforge-${VERSION}-${NEOFORGE_VERSION}-installer.jar"
URL="https://maven.neoforged.net/releases/net/neoforged/neoforge/${VERSION}-${NEOFORGE_VERSION}/${INSTALLER}"

curl -fL "$URL" -o /tmp/neoforge-installer.jar

java -jar /tmp/neoforge-installer.jar --installServer "$DATA_DIR"

log "NeoForge server ready"
