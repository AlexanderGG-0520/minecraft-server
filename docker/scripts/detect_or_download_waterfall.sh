#!/bin/bash
set -euo pipefail
log() { echo "[waterfall] $*"; }

DATA_DIR="/data"
SERVER_JAR="${DATA_DIR}/server.jar"

VERSION=$(curl -fsSL https://api.papermc.io/v2/projects/waterfall | jq -r '.versions[-1]')
BUILD=$(curl -fsSL "https://api.papermc.io/v2/projects/waterfall/versions/${VERSION}" | jq -r '.builds[-1]')

URL="https://api.papermc.io/v2/projects/waterfall/versions/${VERSION}/builds/${BUILD}/downloads/waterfall-${VERSION}-${BUILD}.jar"

log "Downloading Waterfall: $URL"
curl -fSL "$URL" -o "${SERVER_JAR}.tmp"
mv "${SERVER_JAR}.tmp" "${SERVER_JAR}"
log "Installed Waterfall"
