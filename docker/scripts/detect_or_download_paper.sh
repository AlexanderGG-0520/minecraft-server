#!/bin/bash
set -euo pipefail

log() { echo "[paper] $*"; }

MC_VERSION="${VERSION:?VERSION required}"
PAPER_BUILD="${PAPER_BUILD:-latest}"
DATA_DIR="/data"
SERVER_JAR="${DATA_DIR}/server.jar"

log "Paper resolver started (MC=${MC_VERSION}, requested build=${PAPER_BUILD})"

# ----------------------------------------------------------
# 1. Check if paper supports the version
# ----------------------------------------------------------
VERSION_API="https://api.papermc.io/v2/projects/paper/versions"

if ! curl -fsSL "${VERSION_API}" | jq -e --arg v "$MC_VERSION" '.versions | index($v)' >/dev/null; then
  log "ERROR: Paper does not support MC version ${MC_VERSION}"
  exit 1
fi


# ----------------------------------------------------------
# 2. Resolve build number
# ----------------------------------------------------------
BUILDS_API="https://api.papermc.io/v2/projects/paper/versions/${MC_VERSION}"

if [[ "$PAPER_BUILD" == "latest" ]]; then
  PAPER_BUILD=$(curl -fsSL "${BUILDS_API}" | jq -r '.builds[-1]')
  log "Resolved latest Paper build: ${PAPER_BUILD}"
else
  # Validate custom build exists
  if ! curl -fsSL "${BUILDS_API}" | jq -e --argjson b "$PAPER_BUILD" '.builds | index($b)' >/dev/null; then
    log "ERROR: Requested build ${PAPER_BUILD} does not exist for MC ${MC_VERSION}"
    exit 1
  fi
  log "Using user-specified Paper build: ${PAPER_BUILD}"
fi


# ----------------------------------------------------------
# 3. Construct download URL
# ----------------------------------------------------------
DOWNLOAD_URL="https://api.papermc.io/v2/projects/paper/versions/${MC_VERSION}/builds/${PAPER_BUILD}/downloads/paper-${MC_VERSION}-${PAPER_BUILD}.jar"

log "Downloading Paper from: ${DOWNLOAD_URL}"

# ----------------------------------------------------------
# 4. Download
# ----------------------------------------------------------
curl -fsSL "${DOWNLOAD_URL}" -o "${SERVER_JAR}.tmp" || {
  log "ERROR: Failed to download Paper"
  exit 1
}

mv "${SERVER_JAR}.tmp" "${SERVER_JAR}"

log "PaperMC server installed successfully → ${SERVER_JAR}"
