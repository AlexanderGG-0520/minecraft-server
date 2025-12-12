#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data
SERVER_JAR="${DATA_DIR}/server.jar"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [vanilla] $*"
}

[[ -f "$SERVER_JAR" ]] && {
  log "server.jar already exists"
  exit 0
}

VERSION="${VERSION:?VERSION is required}"

log "Downloading Vanilla Minecraft ${VERSION}"

META=$(curl -fsSL https://piston-meta.mojang.com/mc/game/version_manifest.json)
URL=$(echo "$META" | jq -r ".versions[] | select(.id==\"$VERSION\") | .url")

SERVER_URL=$(curl -fsSL "$URL" | jq -r ".downloads.server.url")

curl -fL "$SERVER_URL" -o "$SERVER_JAR"

log "Vanilla server.jar ready"
