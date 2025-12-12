#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data
LAUNCHER_JAR="${DATA_DIR}/fabric-server-launch.jar"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [fabric] $*"
}

[[ -f "$LAUNCHER_JAR" ]] && {
  log "fabric-server-launch.jar already exists"
  exit 0
}

VERSION="${VERSION:?VERSION is required}"
FABRIC_LOADER="${FABRIC_LOADER:-latest}"

log "Installing Fabric ${VERSION} (loader=${FABRIC_LOADER})"

curl -fsSL https://meta.fabricmc.net/v2/versions/installer \
  | jq -r '.[0].url' \
  | xargs curl -fL -o /tmp/fabric-installer.jar

java -jar /tmp/fabric-installer.jar server \
  -mcversion "$VERSION" \
  -loade
