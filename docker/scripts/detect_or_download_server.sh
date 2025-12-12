#!/bin/bash

set -euo pipefail

cd /opt/mc

# ===========================================
# Colors
# ===========================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[server]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[warn]${NC} $1"
}

error() {
    echo -e "${RED}[error]${NC} $1" >&2
}

# ===========================================
# Check existing jar
# ===========================================
if [ -f /data/server.jar ]; then
    log "Existing server.jar found — skipping download"
    exit 0
fi

log "No server.jar found — starting auto download..."

TYPE_LOWER=$(echo "${TYPE:-fabric}" | tr '[:upper:]' '[:lower:]')
VERSION="${VERSION:-latest}"

# ===========================================
# Find loader scripts
# ===========================================
TYPE_DIR="/opt/mc/${TYPE_LOWER}"
DOWNLOAD_SCRIPT="${TYPE_DIR}/download.sh"

if [ ! -f "${DOWNLOAD_SCRIPT}" ]; then
    error "Loader download script not found: ${DOWNLOAD_SCRIPT}"
    error "TYPE=${TYPE_LOWER} is not supported."
    exit 1
fi

log "Using loader: ${TYPE_LOWER}"
log "Loading version: ${VERSION}"
log "Running: ${DOWNLOAD_SCRIPT}"

# ===========================================
# Execute loader
# ===========================================
chmod +x "${DOWNLOAD_SCRIPT}"

if ! "${DOWNLOAD_SCRIPT}" "${VERSION}" /data/server.jar; then
    error "Loader failed to download server jar."
    exit 1
fi

# ===========================================
# Final validation
# ===========================================
if [ ! -s /data/server.jar ]; then
    error "server.jar is missing or empty after download!"
    exit 1
fi

log "server.jar prepared successfully!"
