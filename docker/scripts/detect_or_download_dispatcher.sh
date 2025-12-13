#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$1] $2"
}

SERVER_PID=""

start_server() {
  log INFO "Starting Minecraft server"
  java ${JVM_ARGS} -jar server.jar &
  SERVER_PID=$!
}

shutdown_server() {
  log INFO "Shutting down server"
  rcon stop || true
  wait "$SERVER_PID" || true
  exit 0
}

trap shutdown_server SIGTERM SIGINT

start_server

# dispatcher main loop (PID1)
while true; do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    log ERROR "Minecraft process exited"
    exit 1
  fi

  # ready判定
  if grep -q "Done (" /data/logs/latest.log; then
    touch /data/.ready
  fi

  sleep 1
done
