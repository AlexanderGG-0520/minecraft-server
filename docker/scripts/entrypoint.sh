#!/bin/bash
set -euo pipefail

# ============================================================
#  Logging System (color + timestamp)
# ============================================================

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  local level="$1"
  shift
  local msg="$@"

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

  echo -e "${COLOR}[$(timestamp)] [$level]${RESET} $msg"
}


# ============================================================
#  Error Handling Framework (fatal / retry)
# ============================================================

fatal() {
  log ERROR "$1"
  exit 1
}

retry() {
  local attempts="$1"
  local delay="$2"
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
#  Import Subscripts
# ============================================================

source /opt/mc/scripts/server_download.sh
source /opt/mc/scripts/sync_s3.sh
source /opt/mc/scripts/world_reset.sh


# ============================================================
#  Startup Banner
# ============================================================

log START "Minecraft Runtime Booting..."
log INFO "TYPE=${TYPE}, VERSION=${VERSION}, JAVA=$(java -version 2>&1 | head -n1)"


# ============================================================
#  1. Load Base Configuration
# ============================================================

BASE_ENV="/opt/mc/base/base.env"

log INFO "Loading base layer..."
if [[ -f "$BASE_ENV" ]]; then
  source "$BASE_ENV"
else
  fatal "Missing base.env at $BASE_ENV"
fi


# ============================================================
#  2. Apply TYPE-Specific Layer
# ============================================================

TYPE_DIR="/opt/mc/${TYPE}"

log INFO "Applying TYPE layer: ${TYPE}"

if [[ ! -d "$TYPE_DIR" ]]; then
  fatal "TYPE directory missing: ${TYPE_DIR}"
fi

# Base → TYPE → /data（ユーザー上書き）
retry 3 1 cp -r "$TYPE_DIR"/* /data


# ============================================================
#  3. Sync Mods/Configs from S3 (optional)
# ============================================================

if [[ "${S3_SYNC_ENABLED:-false}" == "true" ]]; then
  log INFO "Running S3 synchronization..."
  retry 5 3 sync_s3_main
fi


# ============================================================
#  4. Download server.jar (TYPE-aware)
# ============================================================

log INFO "Resolving and downloading server.jar..."
retry 5 2 server_download_main

if [[ ! -f /data/server.jar ]]; then
  fatal "server.jar missing after download"
fi


# ============================================================
#  5. World Reset (if reset-world.flag exists)
# ============================================================

if [[ -f "/data/reset-world.flag" ]]; then
  log WARN "reset-world.flag detected — world will be reset"
  retry 3 1 world_reset_main
fi


# ============================================================
#  6. Merge JVM and MC args
# ============================================================

log INFO "Preparing JVM and Minecraft launch arguments"

# jvm args
[[ -f /opt/mc/base/jvm.args ]] && cp /opt/mc/base/jvm.args /data/jvm.args
[[ -f /opt/mc/${TYPE}/jvm.args ]] && cat /opt/mc/${TYPE}/jvm.args >> /data/jvm.args
[[ -f /data/jvm.override ]] && cat /data/jvm.override >> /data/jvm.args

# mc args
[[ -f /opt/mc/base/mc.args ]] && cp /opt/mc/base/mc.args /data/mc.args
[[ -f /opt/mc/${TYPE}/mc.args ]] && cat /opt/mc/${TYPE}/mc.args >> /data/mc.args
[[ -f /data/mc.override ]] && cat /data/mc.override >> /data/mc.args

log DEBUG "Merged JVM args: $(tr '\n' ' ' < /data/jvm.args)"
log DEBUG "Merged MC args: $(tr '\n' ' ' < /data/mc.args)"


# ============================================================
#  7. Start Minecraft Server
# ============================================================

log START "Launching Java runtime..."

exec java $(cat /data/jvm.args) -jar /data/server.jar $(cat /data/mc.args)

fatal "Java process exited unexpectedly"
