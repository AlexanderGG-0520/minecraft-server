#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Logging
# ============================================================
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] [$1] $2"; }
die() { log ERROR "$1"; exit 1; }

# ============================================================
# Paths
# ============================================================
DATA_DIR="${DATA_DIR:-/data}"
READY_FILE="${DATA_DIR}/.server-ready"
RESET_FLAG="${DATA_DIR}/reset-world.flag"
LOG_FILE="${DATA_DIR}/logs/latest.log"

WORLD_NAME="${WORLD_NAME:-world}"

# ============================================================
# Env defaults (減らさない)
# ============================================================
: "${EULA:=false}"
: "${SERVER_PORT:=25569}"
: "${ONLINE_MODE:=true}"

: "${HARDCORE:=false}"
: "${RESET_WORLD_ON_DEATH:=false}"
: "${RESET_WORLD_CONFIRM:=false}"

: "${ENABLE_RCON:=false}"
: "${RCON_PORT:=25575}"
: "${RCON_PASSWORD:=changeme}"
: "${STOP_SERVER_ANNOUNCE_DELAY:=10}"

# Vanilla/Paper系で「Server empty for 60 seconds, pausing」を止めたい場合
# (このプロパティが存在する実装でのみ有効)
: "${PAUSE_WHEN_EMPTY_SECONDS:=-1}"

# ============================================================
# Cache dirs (C2ME / OpenCL 永続)
# ============================================================
export HOME="${DATA_DIR}"
export XDG_CACHE_HOME="${DATA_DIR}/.cache"
export CUDA_CACHE_PATH="${DATA_DIR}/.nv/ComputeCache"
export CUDA_CACHE_MAXSIZE="${CUDA_CACHE_MAXSIZE:-2147483648}"

mkdir -p "${DATA_DIR}/logs" "${XDG_CACHE_HOME}" "${DATA_DIR}/.nv"
rm -f "${READY_FILE}"

# ============================================================
# EULA
# ============================================================
if [[ "${EULA}" == "true" ]]; then
  echo "eula=true" > "${DATA_DIR}/eula.txt"
  log INFO "EULA accepted via env"
else
  [[ -f "${DATA_DIR}/eula.txt" ]] || die "EULA not accepted (set EULA=true)"
fi

# ============================================================
# Hardcore World Reset
# ============================================================
maybe_reset_world() {
  [[ "${HARDCORE}" == "true" ]] || return 0
  [[ "${RESET_WORLD_ON_DEATH}" == "true" ]] || return 0
  [[ -f "${RESET_FLAG}" ]] || return 0

  [[ "${RESET_WORLD_CONFIRM}" == "true" ]] || die "reset-world.flag present but RESET_WORLD_CONFIRM!=true (safety stop)"

  log WARN "Hardcore world reset triggered"

  for w in \
    "${DATA_DIR}/${WORLD_NAME}" \
    "${DATA_DIR}/${WORLD_NAME}_nether" \
    "${DATA_DIR}/${WORLD_NAME}_the_end"
  do
    if [[ -d "$w" ]]; then
      log WARN "Removing world directory: $w"
      rm -rf "$w"
    fi
  done

  rm -f "${RESET_FLAG}"
  log INFO "World reset completed"
}
maybe_reset_world

# ============================================================
# server.properties
# ============================================================
if [[ ! -f "${DATA_DIR}/server.properties" ]]; then
  cat > "${DATA_DIR}/server.properties" <<EOF
server-port=${SERVER_PORT}
online-mode=${ONLINE_MODE}
hardcore=${HARDCORE}

# Prevent "Server empty for 60 seconds, pausing" if supported
pause-when-empty-seconds=${PAUSE_WHEN_EMPTY_SECONDS}
EOF
else
  # 既存がある場合も、pause-when-empty-secondsだけは上書きしたいならここで追記/置換してもOK
  if grep -q '^pause-when-empty-seconds=' "${DATA_DIR}/server.properties"; then
    sed -i "s/^pause-when-empty-seconds=.*/pause-when-empty-seconds=${PAUSE_WHEN_EMPTY_SECONDS}/" "${DATA_DIR}/server.properties" || true
  else
    echo "pause-when-empty-seconds=${PAUSE_WHEN_EMPTY_SECONDS}" >> "${DATA_DIR}/server.properties"
  fi
fi

# ============================================================
# JVM / MC args
# ============================================================
JVM_ARGS="$(grep -v '^\s*#' "${DATA_DIR}/jvm.args" 2>/dev/null | grep -v '^\s*$' | xargs || true)"
MC_ARGS="$(grep -v '^\s*#' "${DATA_DIR}/mc.args" 2>/dev/null | grep -v '^\s*$' | xargs || true)"

# ============================================================
# Readiness watcher (log-based)
# ============================================================
readiness_watcher() {
  until [[ -f "${LOG_FILE}" ]]; do sleep 1; done

  # 「Done (..)! For help, type "help"」が出たらready
  tail -Fn0 "${LOG_FILE}" | while read -r line; do
    if [[ "$line" == *'Done ('*'For help, type "help"'* ]]; then
      touch "${READY_FILE}"
      log INFO "Server READY (ready-file created: ${READY_FILE})"
      break
    fi
  done
}

readiness_watcher &

# ============================================================
# RCON helper
# ============================================================
rcon_send() {
  local cmd="$1"
  # rcon-cli が入ってる前提。無い場合は黙ってスキップ。
  command -v rcon-cli >/dev/null 2>&1 || return 0
  timeout 3 rcon-cli --host 127.0.0.1 --port "${RCON_PORT}" --password "${RCON_PASSWORD}" <<<"${cmd}" >/dev/null 2>&1 || true
}

# ============================================================
# Shutdown (RCON) - works because we DON'T exec java
# ============================================================
MC_PID=""

shutdown() {
  log INFO "Shutdown requested (signal received)"

  if [[ "${ENABLE_RCON}" == "true" ]]; then
    rcon_send "say Server shutting down in ${STOP_SERVER_ANNOUNCE_DELAY}s"
    sleep "${STOP_SERVER_ANNOUNCE_DELAY}"
    rcon_send "stop"
  fi

  # javaプロセスを落とす保険（RCON stop が効かなかった場合）
  if [[ -n "${MC_PID}" ]] && kill -0 "${MC_PID}" 2>/dev/null; then
    log WARN "Killing MC process as fallback (pid=${MC_PID})"
    kill -TERM "${MC_PID}" 2>/dev/null || true
  fi

  exit 0
}
trap shutdown SIGTERM SIGINT

# ============================================================
# Launch
# ============================================================
log INFO "Launching Minecraft server (hardcore=${HARDCORE}, port=${SERVER_PORT})"

if [[ -f "${DATA_DIR}/fabric-server-launch.jar" ]]; then
  # Fabricは gameJarPath が必要な環境がある
  if [[ -f "${DATA_DIR}/server.jar" ]]; then
    java -Dfabric.gameJarPath="${DATA_DIR}/server.jar" ${JVM_ARGS} -jar "${DATA_DIR}/fabric-server-launch.jar" ${MC_ARGS} &
  else
    java ${JVM_ARGS} -jar "${DATA_DIR}/fabric-server-launch.jar" ${MC_ARGS} &
  fi
elif [[ -f "${DATA_DIR}/server.jar" ]]; then
  java ${JVM_ARGS} -jar "${DATA_DIR}/server.jar" ${MC_ARGS} &
else
  die "No server jar found in ${DATA_DIR}"
fi

MC_PID=$!
log INFO "Minecraft started (pid=${MC_PID})"

# 子プロセス終了まで待つ
wait "${MC_PID}"
exit_code=$?

log WARN "Minecraft exited (code=${exit_code})"
exit "${exit_code}"
