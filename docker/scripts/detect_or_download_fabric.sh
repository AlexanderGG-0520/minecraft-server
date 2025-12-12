#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data
SERVER_JAR="${DATA_DIR}/server.jar"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [fabric] $*"
}

[[ -f "$SERVER_JAR" ]] && {
  log "server.jar already exists"
  exit 0
}

VERSION="${VERSION:?VERSION is required}"
FABRIC_LOADER="${FABRIC_LOADER:-latest}"
INSTALLER_VERSION="${FABRIC_INSTALLER_VERSION:-latest}"

log "Installing Fabric ${VERSION} (loader=${FABRIC_LOADER})"

curl -fL https://meta.fabricmc.net/v2/versions/installer \
  | jq -r '.[0].url' \
  | xargs curl -fL -o /tmp/fabric-installer.jar

java -jar /tmp/fabric-installer.jar server \
  -mcversion "$VERSION" \
  -loader "$FABRIC_LOADER" \
  -downloadMinecraft \
  -dir "$DATA_DIR"

mv "$DATA_DIR/fabric-server-launch.jar" "$SERVER_JAR"

log "Fabric server.jar ready"
