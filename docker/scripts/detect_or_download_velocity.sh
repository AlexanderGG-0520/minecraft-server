#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data
JAR="${DATA_DIR}/velocity.jar"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [velocity] $*"
}

[[ -f "$JAR" ]] && {
  log "velocity.jar already exists"
  exit 0
}

VERSION="${VELOCITY_VERSION:-latest}"

log "Downloading Velocity ${VERSION}"

curl -fL https://api.papermc.io/v2/projects/velocity/versions \
  | jq -r '.versions[-1]' \
  | xargs -I{} curl -fL \
    "https://api.papermc.io/v2/projects/velocity/versions/{}/builds/$(curl -fsSL https://api.papermc.io/v2/projects/velocity/versions/{}/builds | jq -r '.builds[-1]')/downloads/velocity-{}-$(curl -fsSL https://api.papermc.io/v2/projects/velocity/versions/{}/builds | jq -r '.builds[-1]').jar" \
  -o "$JAR"

log "Velocity ready"
