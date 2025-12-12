#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data
SERVER_JAR="${DATA_DIR}/server.jar"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [paper] $*"
}

[[ -f "$SERVER_JAR" ]] && {
  log "server.jar already exists"
  exit 0
}

VERSION="${VERSION:?VERSION required}"

log "Downloading Paper ${VERSION}"

BUILD=$(curl -fsSL https://api.papermc.io/v2/projects/paper/versions/${VERSION} \
  | jq -r '.builds[-1]')

URL="https://api.papermc.io/v2/projects/paper/versions/${VERSION}/builds/${BUILD}/downloads/paper-${VERSION}-${BUILD}.jar"

curl -fL "$URL" -o "$SERVER_JAR"

log "Paper server.jar downloaded"
