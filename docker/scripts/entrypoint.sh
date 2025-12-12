#!/bin/bash
set -euo pipefail

# ============================================================
#  Logging
# ============================================================

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log() {
  local level="$1"; shift
  local msg="$*"

  local RESET="\033[0m"
  local RED="\033[31m"
  local GREEN="\033[32m"
  local YELLOW="\033[33m"
  local CYAN="\033[36m"
  local MAGENTA="\033[35m"

  case "$level" in
    INFO)  COLOR="$GREEN" ;;
    WARN)  COLOR="$YELLOW" ;;
    ERROR) COLOR="$RED" ;;
    DEBUG) COLOR="$CYAN" ;;
    START) COLOR="$MAGENTA" ;;
    *)     COLOR="$RESET" ;;
  esac

  echo -e "${COLOR}[$(timestamp)] [$level]${RESET} ${msg}"
}

fatal() { log ERROR "$1"; exit 1; }

retry() {
  local attempts="$1"; local delay="$2"
  shift 2
  local n=0
  until "$@"; do
    n=$((n+1))
    if [[ "$n" -ge "$attempts" ]]; then
      fatal "Command failed after ${attempts} attempts: $*"
    fi
    log WARN "Retry $n/$attempts: $*"
    sleep "$delay"
  done
}

# ============================================================
#  Import helper scripts
# ============================================================

source /opt/mc/scripts/sync_s3.sh
source /opt/mc/scripts/reset_world.sh
source /opt/mc/base/make_args.sh

DETECT_DL="/opt/mc/scripts/detect_or_download_server.sh"

# ============================================================
#  Reset world early (before data population)
# ============================================================

if [[ -f "/data/reset-world.flag" ]]; then
  log WARN "reset-world.flag detected — resetting world"
  retry 3 1 reset_world_main

  # flagはここで削除しておかないと永遠にリセットされ続ける
  rm -f /data/reset-world.flag
  log INFO "reset-world.flag consumed and removed."
fi


# ============================================================
#  Startup banner
# ============================================================

log START "Minecraft Runtime Booting..."
log INFO "TYPE=${TYPE}, VERSION=${VERSION}, JAVA=$(java -version 2>&1 | head -n1)"


# ============================================================
#  Load base.env
# ============================================================

BASE_ENV="/opt/mc/base/base.env"
log INFO "Loading base layer..."

if [[ -f "$BASE_ENV" ]]; then
  source "$BASE_ENV"
else
  fatal "Missing base.env at $BASE_ENV"
fi


# ============================================================
#  Apply TYPE-specific layer
# ============================================================

TYPE_DIR="/opt/mc/${TYPE}"

log INFO "Applying TYPE layer: ${TYPE}"

if [[ ! -d "$TYPE_DIR" ]]; then
  fatal "TYPE directory missing: ${TYPE_DIR}"
fi

retry 3 1 cp -r "$TYPE_DIR"/* /data

# ============================================================
#  Run S3 sync (optional)
# ============================================================

if [[ "${S3_SYNC_ENABLED:-false}" == "true" ]]; then
  log INFO "Running S3 synchronization..."
  retry 5 3 sync_s3_main
fi

# ============================================================
#  Detect or download server.jar
# ============================================================

log INFO "Resolving Minecraft server.jar..."

case "$TYPE" in
  vanilla)
    bash /opt/mc/scripts/detect_or_download_vanilla.sh ;;
  fabric)
    bash /opt/mc/scripts/detect_or_download_fabric.sh ;;
  forge)
    bash /opt/mc/scripts/detect_or_download_forge.sh ;;
  neoforge)
    bash /opt/mc/scripts/detect_or_download_neoforge.sh ;;
  paper)
    bash /opt/mc/scripts/detect_or_download_paper.sh ;;
  purpur)
    bash /opt/mc/scripts/detect_or_download_purpur.sh ;;
  velocity)
    bash /opt/mc/scripts/detect_or_download_velocity.sh ;;
  waterfall)
    bash /opt/mc/scripts/detect_or_download_waterfall.sh ;;
  bungeecord)
    bash /opt/mc/scripts/detect_or_download_bungeecord.sh ;;
  *)
    fatal "Unknown TYPE=${TYPE}" ;;
esac

# ============================================================
#  Merge JVM / MC args
# ============================================================

log INFO "Preparing JVM and Minecraft args"

[[ -f /opt/mc/base/jvm.args ]] && cp /opt/mc/base/jvm.args /data/jvm.args
[[ -f /opt/mc/${TYPE}/jvm.args ]] && cat /opt/mc/${TYPE}/jvm.args >> /data/jvm.args
[[ -f /data/jvm.override ]] && cat /data/jvm.override >> /data/jvm.args

[[ -f /opt/mc/base/mc.args ]] && cp /opt/mc/base/mc.args /data/mc.args
[[ -f /opt/mc/${TYPE}/mc.args ]] && cat /opt/mc/${TYPE}/mc.args >> /data/mc.args
[[ -f /data/mc.override ]] && cat /data/mc.override >> /data/mc.args

# ============================================================
#  Generate server.properties (FULL version)
# ============================================================

log INFO "Generating server.properties..."

SP_BASE="/opt/mc/base/server.properties.base"
SP_TYPE="/opt/mc/${TYPE}/server.properties"
SP_OUT="/data/server.properties"

tmp_sp="$(mktemp)"

# base load
cp "$SP_BASE" "$tmp_sp" || fatal "Missing base server.properties"

# TYPE override
if [[ -f "$SP_TYPE" ]]; then
  while IFS='=' read -r key val; do
    [[ "$key" == \#* || -z "$key" ]] && continue
    sed -i "s|^${key}=.*|${key}=${val}|" "$tmp_sp" || true
  done < "$SP_TYPE"
fi

# helper
set_prop() {
  local key="$1"; local env="$2"
  local val="${!env:-}"
  [[ -n "$val" ]] && sed -i "s|^${key}=.*|${key}=${val}|" "$tmp_sp"
}

# 全ての server.properties 公式キー
set_prop "motd"                          "MOTD"
set_prop "difficulty"                    "DIFFICULTY"
set_prop "gamemode"                      "MODE"
set_prop "max-players"                   "MAX_PLAYERS"
set_prop "online-mode"                   "ONLINE_MODE"
set_prop "allow-flight"                  "ALLOW_FLIGHT"
set_prop "enable-command-block"          "ENABLE_COMMAND_BLOCK"
set_prop "view-distance"                 "VIEW_DISTANCE"
set_prop "simulation-distance"           "SIMULATION_DISTANCE"
set_prop "enforce-whitelist"             "ENFORCE_WHITELIST"
set_prop "white-list"                    "WHITE_LIST"
set_prop "pvp"                           "PVP"
set_prop "hardcore"                      "HARDCORE"
set_prop "level-type"                    "LEVEL_TYPE"
set_prop "level-seed"                    "SEED"
set_prop "spawn-protection"              "SPAWN_PROTECTION"
set_prop "server-port"                   "SERVER_PORT"
set_prop "sync-chunk-writes"             "SYNC_CHUNK_WRITES"
set_prop "max-world-size"                "MAX_WORLD_SIZE"
set_prop "player-idle-timeout"           "IDLE_TIMEOUT"
set_prop "resource-pack"                 "RESOURCE_PACK_URL"
set_prop "resource-pack-sha1"            "RESOURCE_PACK_SHA1"
set_prop "rate-limit"                    "RATE_LIMIT"
set_prop "network-compression-threshold" "NETWORK_COMPRESSION"
set_prop "entity-broadcast-range-percentage" "ENTITY_BROADCAST_PCT"
set_prop "max-chained-neighbor-updates"  "MAX_CHAINED_UPDATES"
set_prop "hide-online-players"           "HIDE_PLAYERS"

# write
cp "$tmp_sp" "$SP_OUT"
log INFO "server.properties generated."

# ============================================================
#  Launch Java
# ============================================================

log START "Launching Minecraft Server..."

exec java $(cat /data/jvm.args) -jar /data/server.jar $(cat /data/mc.args)

fatal "Java exited unexpectedly"
