#!/bin/bash

# ============================================================
# Minecraft Runtime Health Check (Pro Edition)
# ============================================================

set -e

# ---------- Logging (minimal, no colors for K8s) ----------
timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  echo "[$(timestamp)] [HEALTHCHECK] $1"
}

# ---------- 1. Java process check ----------
PID=$(pgrep -f "java.*minecraft" || true)

if [[ -z "$PID" ]]; then
  log "Java process not found — server is DOWN"
  exit 1
fi

# ---------- 2. Port check (25565) ----------
if ! timeout 1 bash -c "</dev/tcp/127.0.0.1/25565" 2>/dev/null; then
  log "Minecraft server port 25565 is not responding"
  exit 1
fi

# ---------- 3. RCON check (optional) ----------
if [[ "${ENABLE_RCON:-false}" == "true" ]]; then
  if ! rcon-cli list > /dev/null 2>&1; then
    log "RCON not responding"
    exit 1
  fi
fi

# ---------- 4. Crash detection ----------
if grep -q "Exception" /data/logs/latest.log 2>/dev/null; then
  log "Crash keywords detected in logs"
  exit 1
fi

# ---------- 5. JVM Heap monitoring ----------
HEAP_USED=$(jcmd "$PID" GC.heap_info 2>/dev/null | awk '/used/ {print $3}' || echo "0")
HEAP_MAX=$(jcmd "$PID" GC.heap_info 2>/dev/null | awk '/max_capacity/ {print $3}' || echo "1")

if [[ "$HEAP_USED" -gt "$((HEAP_MAX * 90 / 100))" ]]; then
  log "JVM heap usage critical: ${HEAP_USED} / ${HEAP_MAX}"
  exit 1
fi

# ---------- PASS ----------
log "Healthy (PID=$PID, Heap=${HEAP_USED}/${HEAP_MAX})"
exit 0
