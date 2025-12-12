#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data
LAUNCHER_JAR="${DATA_DIR}/fabric-server-launch.jar"
SERVER_JAR="${DATA_DIR}/server.jar"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [fabric] $*"
}

if [[ -f "$LAUNCHER_JAR" && -f "$SERVER_JAR" ]]; then
  log "Fabric launcher and server.jar already exist"
  exit 0
fi

VERSION="${VERSION:?VERSION is required}"
FABRIC_LOADER="${FABRIC_LOADER:-latest}"

log "Installing Fabric ${VERSION} (loader=${FABRIC_LOADER})"

curl -fsSL https://meta.fabricmc.net/v2/versions/installer \
  | jq -r '.[0].url' \
  | xargs curl -fL -o /tmp/fabric-installer.jar

java -jar /tmp/fabric-installer.jar server \
  -mcversion "$VERSION" \
  -loader "$FABRIC_LOADER" \
  -downloadMinecraft \
  -dir "$DATA_DIR"

log "Fabric server ready (launcher + game jar)"
