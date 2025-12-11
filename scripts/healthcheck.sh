#!/usr/bin/env bash
set -euo pipefail

log() { echo "[health] $*"; }

PORT="${SERVER_PORT:-25565}"

# 1. server.jar が存在するか？
if [[ ! -f /data/server.jar ]]; then
  log "server.jar not found"
  exit 1
fi

# 2. Minecraft ポートの TCP レベルチェック
# OS レベルで listen しているかを確認
if ! (echo > /dev/tcp/127.0.0.1/"${PORT}") >/dev/null 2>&1; then
  log "Minecraft port ${PORT} is not responding"
  exit 1
fi

# 3. （任意）Ping プロトコルチェック
if [[ "${HEALTHCHECK_PING:-false}" == "true" ]]; then
  if ! mcstatus localhost ping >/dev/null 2>&1; then
    log "mcstatus ping failed"
    exit 1
  fi
fi

log "healthy"
exit 0
