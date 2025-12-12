#!/bin/bash
set -euo pipefail

# ========================================================================
#  Logging utilities
# ========================================================================
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

# ========================================================================
#  Import modules
# ========================================================================

source /opt/mc/scripts/sync_s3.sh
source /opt/mc/scripts/reset_world.sh
source /opt/mc/base/make_args.sh

# detect/download scripts
DL_VANILLA=/opt/mc/scripts/detect_or_download_vanilla.sh
DL_FABRIC=/opt/mc/scripts/detect_or_download_fabric.sh
DL_FORGE=/opt/mc/scripts/detect_or_download_forge.sh
DL_NEOFORGE=/opt/mc/scripts/detect_or_download_neoforge.sh
DL_PAPER=/opt/mc/scripts/detect_or_download_paper.sh
DL_PURPUR=/opt/mc/scripts/detect_or_download_purpur.sh
DL_VELOCITY=/opt/mc/scripts/detect_or_download_velocity.sh
DL_WATERFALL=/opt/mc/scripts/detect_or_download_waterfall.sh
DL_BUNGEECORD=/opt/mc/scripts/detect_or_download_bungeecord.sh

TYPE_LOWER="$(echo "${TYPE:-vanilla}" | tr '[:upper:]' '[:lower:]')"


# ========================================================================
#  Reset world early
# ========================================================================

if [[ -f "/data/reset-world.flag" ]]; then
  log WARN "reset-world.flag detected — resetting world"
  retry 3 1 reset_world_main
  rm -f /data/reset-world.flag || true
  log INFO "reset-world.flag consumed and removed."
fi

# ========================================================================
#  Startup banner
# ========================================================================

log START "Minecraft Runtime Booting..."
log INFO "TYPE=${TYPE} (${TYPE_LOWER}), VERSION=${VERSION}, JAVA=$(java -version 2>&1 | head -n1)"

# ========================================================================
#  Load base.env
# ========================================================================

BASE_ENV="/opt/mc/base/base.env"
log INFO "Loading base.env (default configs)"

if [[ -f "$BASE_ENV" ]]; then
  set -a
  source "$BASE_ENV"
  set +a
else
  fatal "Missing base.env: ${BASE_ENV}"
fi

log INFO "base.env loaded."


# ========================================================================
#  Apply TYPE-specific layer
# ========================================================================

TYPE_DIR="/opt/mc/${TYPE_LOWER}"

log INFO "Applying TYPE layer: ${TYPE_LOWER}"

if [[ ! -d "${TYPE_DIR}" ]]; then
  fatal "TYPE directory missing: ${TYPE_DIR}"
fi

retry 3 1 cp -r "${TYPE_DIR}"/* /data


# ========================================================================
#  S3 Sync
# ========================================================================

if [[ "${S3_SYNC_ENABLED:-false}" == "true" ]]; then
  log INFO "Running S3 synchronization"
  retry 5 3 sync_s3_main
fi


# ========================================================================
#  Detect or download server.jar
# ========================================================================

log INFO "Resolving server implementation..."

case "$TYPE_LOWER" in
  vanilla)     bash "$DL_VANILLA"     ;;
  fabric)      bash "$DL_FABRIC"      ;;
  forge)       bash "$DL_FORGE"       ;;
  neoforge)    bash "$DL_NEOFORGE"    ;;
  paper)       bash "$DL_PAPER"       ;;
  purpur)      bash "$DL_PURPUR"      ;;
  velocity)    bash "$DL_VELOCITY"    ;;
  waterfall)   bash "$DL_WATERFALL"   ;;
  bungeecord)  bash "$DL_BUNGEECORD"  ;;
  *)
    fatal "Unknown TYPE=${TYPE} (normalized: ${TYPE_LOWER})"
    ;;
esac

[[ -f /data/server.jar ]] || fatal "server.jar missing after detection/download"


# ========================================================================
#  Prepare JVM / MC args
# ========================================================================

log INFO "Generating JVM & MC args via make_args.sh..."

retry 3 1 build_jvm_args
retry 3 1 build_mc_args

log INFO "JVM args ready: $(tr '\n' ' ' < /data/jvm.args)"
log INFO "MC args ready:  $(tr '\n' ' ' < /data/mc.args)"


# ========================================================================
#  Generate server.properties
# ========================================================================

log INFO "Generating server.properties..."

SP_BASE="/opt/mc/base/server.properties.base"
SP_TYPE="/opt/mc/${TYPE_LOWER}/server.properties"
SP_OUT="/data/server.properties"

cp "$SP_BASE" "$SP_OUT" || fatal "Missing base server.properties.base"

# type overrides
if [[ -f "$SP_TYPE" ]]; then
  while IFS='=' read -r key val; do
    [[ "$key" =~ ^# || -z "$key" ]] && continue
    sed -i "s|^${key}=.*|${key}=${val}|" "$SP_OUT" || true
  done < "$SP_TYPE"
fi

# env overrides
set_prop() {
  local key="$1"; local env="$2"
  local val="${!env:-}"
  [[ -n "$val" ]] && sed -i "s|^${key}=.*|${key}=${val}|" "$SP_OUT"
}

set_prop "motd" "MOTD"
set_prop "difficulty" "DIFFICULTY"
set_prop "gamemode" "MODE"
set_prop "max-players" "MAX_PLAYERS"
set_prop "online-mode" "ONLINE_MODE"
set_prop "allow-flight" "ALLOW_FLIGHT"
set_prop "enable-command-block" "ENABLE_COMMAND_BLOCK"
set_prop "view-distance" "VIEW_DISTANCE"
set_prop "simulation-distance" "SIMULATION_DISTANCE"
set_prop "level-type" "LEVEL_TYPE"
set_prop "level-seed" "SEED"
set_prop "spawn-protection" "SPAWN_PROTECTION"
set_prop "resource-pack" "RESOURCE_PACK"
set_prop "resource-pack-sha1" "RESOURCE_PACK_SHA1"
set_prop "rate-limit" "RATE_LIMIT"
set_prop "pvp" "PVP"

log INFO "server.properties generated."


# ========================================================================
#  Launch Minecraft
# ========================================================================

log START "Launching Minecraft Server..."

exec java $(cat /data/jvm.args) -jar /data/server.jar $(cat /data/mc.args)

fatal "Java exited unexpectedly"
