#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data
SERVER_JAR="${DATA_DIR}/server.jar"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [purpur] $*"
}

[[ -f "$SERVER_JAR" ]] && {
  log "server.jar already exists"
  exit 0
}

VERSION="${VERSION:?VERSION is required}"

log "Downloading Purpur ${VERSION}"

# 最新 build を取得
BUILD=$(curl -fsSL "https://api.purpurmc.org/v2/purpur/${VERSION}" | jq -r '.builds.latest')

curl -fL \
  "https://api.purpurmc.org/v2/purpur/${VERSION}/${BUILD}/download" \
  -o "$SERVER_JAR"

log "Purpur server.jar ready"
