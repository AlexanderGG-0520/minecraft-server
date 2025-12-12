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

VERSION="${VERSION:-latest}"

log "Downloading Vanilla server ${VERSION}"

if [[ "$VERSION" == "latest" ]]; then
  META_URL="https://launchermeta.mojang.com/mc/game/version_manifest.json"
  VERSION="$(curl -fsSL "$META_URL" | jq -r '.latest.release')"
fi

VERSION_JSON="$(curl -fsSL https://launchermeta.mojang.com/mc/game/version_manifest.json \
  | jq -r ".versions[] | select(.id==\"${VERSION}\") | .url")"

SERVER_URL="$(curl -fsSL "$VERSION_JSON" | jq -r '.downloads.server.url')"

curl -fL "$SERVER_URL" -o "$SERVER_JAR"

log "Vanilla server.jar downloaded"
