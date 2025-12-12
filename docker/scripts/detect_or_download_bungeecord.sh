#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data
JAR="${DATA_DIR}/bungeecord.jar"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [bungeecord] $*"
}

[[ -f "$JAR" ]] && {
  log "bungeecord.jar already exists"
  exit 0
}

log "Downloading BungeeCord"

curl -fL https://ci.md-5.net/job/BungeeCord/lastSuccessfulBuild/artifact/bootstrap/target/BungeeCord.jar \
  -o "$JAR"

log "BungeeCord ready"
