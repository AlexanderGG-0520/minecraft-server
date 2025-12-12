#!/bin/bash
set -euo pipefail
log() { echo "[velocity] $*"; }

MC_VERSION="${VERSION:?VERSION required}"
DATA_DIR="/data"
SERVER_JAR="${DATA_DIR}/server.jar"

log "Velocity resolver started (MC=${MC_VERSION})"

# 1. Resolve latest version series
LATEST_SERIES=$(curl -fsSL "https://api.velocitypowered.com/versions/velocity/latest" | jq -r '.version')
log "Latest Velocity version: ${LATEST_SERIES}"

# 2. Resolve latest build
BUILD=$(curl -fsSL "https://api.velocitypowered.com/versions/velocity/${LATEST_SERIES}/builds" | jq -r '.latest')
log "Velocity build=${BUILD}"

# 3. Download
URL="https://api.velocitypowered.com/versions/velocity/${LATEST_SERIES}/builds/${BUILD}/download"
log "Downloading velocity: ${URL}"

curl -fSL "$URL" -o "${SERVER_JAR}.tmp"
mv "${SERVER_JAR}.tmp" "${SERVER_JAR}"

log "Velocity installed → ${SERVER_JAR}"
