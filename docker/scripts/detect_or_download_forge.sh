#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [forge] $*"
}

[[ -f "$DATA_DIR/run.sh" ]] && {
  log "Forge already installed"
  exit 0
}

VERSION="${VERSION:?VERSION is required}"
FORGE_VERSION="${FORGE_VERSION:?FORGE_VERSION is required}"

log "Installing Forge ${VERSION}-${FORGE_VERSION}"

curl -fL \
  "https://maven.minecraftforge.net/net/minecraftforge/forge/${VERSION}-${FORGE_VERSION}/forge-${VERSION}-${FORGE_VERSION}-installer.jar" \
  -o /tmp/forge-installer.jar

java -jar /tmp/forge-installer.jar --installServer "$DATA_DIR"

chmod +x "$DATA_DIR/run.sh"

log "Forge server ready"
