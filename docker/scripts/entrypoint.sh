#!/bin/bash
set -euo pipefail

# ============================================================
# Logging
# ============================================================

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log() {
  local level="$1"; shift
  local msg="$*"

  local RESET="\033[0m"
  local GREEN="\033[32m"
  local YELLOW="\033[33m"
  local RED="\033[31m"
  local CYAN="\033[36m"
  local MAGENTA="\033[35m"

  case "$level" in
    INFO) COLOR="$GREEN" ;;
    WARN) COLOR="$YELLOW" ;;
    ERROR) COLOR="$RED" ;;
    DEBUG) COLOR="$CYAN" ;;
    START) COLOR="$MAGENTA" ;;
    *) COLOR="$RESET" ;;
  esac

  echo -e "${COLOR}[$(timestamp)] [$level]${RESET} $msg"
}

fatal() { log ERROR "$1"; exit 1; }

retry() {
  local attempts="$1"; local delay="$2"; shift 2
  local n=0
  until "$@"; do
    n=$((n+1))
    [[ $n -ge $attempts ]] && fatal "Command failed: $*"
    log WARN "Retry $n/$attempts: $*"
    sleep "$delay"
  done
}

# ============================================================
# Imports
# ============================================================

source /opt/mc/scripts/sync_s3.sh
source /opt/mc/scripts/reset_world.sh
source /opt/mc/base/make_args.sh

# type detectors
DETECT_BASE="/opt/mc/scripts/detect_or_download"

# Ensure JAVA_VERSION exists
JAVA_VERSION="${JAVA_VERSION:?JAVA_VERSION must be embedded in the Docker image}"


# ============================================================
# Early world reset (before configs)
# ============================================================

if [[ -f "/data/reset-world.flag" ]]; then
  log WARN "Resetting world because reset-world.flag exists"
  retry 3 1 reset_world_main
  rm -f /data/reset-world.flag
  log INFO "reset-world.flag consumed."
fi


# ============================================================
# Startup
# ============================================================

log START "Minecraft Runtime Booting..."
log INFO "TYPE=${TYPE}, VERSION=${VERSION}, JAVA_VERSION=${JAVA_VERSION}"
log INFO "Java: $(java -version 2>&1 | head -n1)"


# ============================================================
# Load base.env
# ============================================================

BASE_ENV="/opt/mc/base/base.env"

if [[ -f "$BASE_ENV" ]]; then
  log INFO "Loading base.env"
  source "$BASE_ENV"
else
  fatal "Missing base.env at $BASE_ENV"
fi


# ============================================================
# Apply TYPE directory
# ============================================================

TYPE_DIR="/opt/mc/${TYPE}"

if [[ ! -d "$TYPE_DIR" ]]; then
  fatal "Missing TYPE directory: ${TYPE_DIR}"
fi

log INFO "Applying TYPE layer: ${TYPE}"

retry 3 1 cp -r "${TYPE_DIR}/"* /data || true


# ============================================================
# S3 Sync
# ============================================================

if [[ "${S3_SYNC_ENABLED:-false}" == "true" ]]; then
  log INFO "Running S3 Sync..."
  retry 5 2 sync_s3_main
fi


# ============================================================
# Detect or download server.jar
# ============================================================

log INFO "Resolving server.jar"

case "${TYPE,,}" in
  vanilla)    bash "${DETECT_BASE}_vanilla.sh" ;;
  fabric)     bash "${DETECT_BASE}_fabric.sh" ;;
  forge)      bash "${DETECT_BASE}_forge.sh" ;;
  neoforge)   bash "${DETECT_BASE}_neoforge.sh" ;;
  paper)      bash "${DETECT_BASE}_paper.sh" ;;
  purpur)     bash "${DETECT_BASE}_purpur.sh" ;;
  velocity)   bash "${DETECT_BASE}_velocity.sh" ;;
  waterfall)  bash "${DETECT_BASE}_waterfall.sh" ;;
  bungeecord) bash "${DETECT_BASE}_bungeecord.sh" ;;
  *)          fatal "Unknown TYPE=${TYPE}" ;;
esac

[[ ! -f /data/server.jar ]] &&
  fatal "server.jar missing! detect script failed"


# ============================================================
# Generate server.properties
# ============================================================

bash /opt/mc/base/generate_server_properties.sh


# ============================================================
# Type-specific configuration
# ============================================================

bash /opt/mc/base/generate_type_config.sh


# ============================================================
# JVM / MC args
# ============================================================

log INFO "Generating JVM / MC args"

retry 3 1 make_args_main


# ============================================================
# OPs / Whitelist auto-add
# ============================================================

bash /opt/mc/scripts/apply_ops_and_whitelist.sh


# ============================================================
# Launch Minecraft
# ============================================================

log START "Launching Java..."

exec java $(cat /data/jvm.args) -jar /data/server.jar $(cat /data/mc.args)

fatal "Minecraft exited unexpectedly"
