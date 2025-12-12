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
  local RED="\033[31m"
  local GREEN="\033[32m"
  local YELLOW="\033[33m"
  local CYAN="\033[36m"
  local MAGENTA="\033[35m"

  case "$level" in
    INFO)  COLOR="$GREEN" ;;
    WARN)  COLOR="$YELLOW" ;;
    ERROR) COLOR="$RED" ;;
    START) COLOR="$MAGENTA" ;;
    DEBUG) COLOR="$CYAN" ;;
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
    if [[ $n -ge $attempts ]]; then
      fatal "Command failed after ${attempts} attempts: $*"
    fi
    log WARN "Retry $n/$attempts ..."
    sleep "$delay"
  done
}


# ============================================================
# Script Paths
# ============================================================

SYNC_S3="/opt/mc/scripts/sync_s3.sh"
RESET_WORLD="/opt/mc/scripts/reset_world.sh"
TYPE_CONFIG="/opt/mc/scripts/type-config.sh"

MAKE_ARGS="/opt/mc/base/make_args.sh"

DL_FABRIC="/opt/mc/scripts/detect_or_download_fabric.sh"
DL_FORGE="/opt/mc/scripts/detect_or_download_forge.sh"
DL_NEOFORGE="/opt/mc/scripts/detect_or_download_neoforge.sh"
DL_VANILLA="/opt/mc/scripts/detect_or_download_vanilla.sh"
DL_PAPER="/opt/mc/scripts/detect_or_download_paper.sh"
DL_PURPUR="/opt/mc/scripts/detect_or_download_purpur.sh"
DL_VELOCITY="/opt/mc/scripts/detect_or_download_velocity.sh"
DL_WATERFALL="/opt/mc/scripts/detect_or_download_waterfall.sh"
DL_BUNGEECORD="/opt/mc/scripts/detect_or_download_bungeecord.sh"


# ============================================================
# EARLY: world reset (before loading anything)
# ============================================================

if [[ -f "/data/reset-world.flag" ]]; then
  log WARN "reset-world.flag detected — running early reset"
  bash "$RESET_WORLD"
  rm -f /data/reset-world.flag || true
  log INFO "World reset complete and flag removed."
fi


# ============================================================
# Startup banner
# ============================================================

log START "Minecraft Runtime Booting..."
log INFO "TYPE=${TYPE}, VERSION=${VERSION}, JAVA=$(java -version 2>&1 | head -n1)"


# ============================================================
# Load base.env without overwriting existing environment
# ============================================================

BASE_ENV="/opt/mc/base/base.env"
log INFO "Loading base.env (default configs)"

if [[ -f "$BASE_ENV" ]]; then
  # Read line-by-line, but DO NOT override existing env vars
  while IFS='=' read -r key val; do
    [[ -z "$key" || "$key" == \#* ]] && continue

    # すでに環境変数がセットされていないときだけ代入
    if [[ -z "${!key:-}" ]]; then
      export "${key}=${val}"
    fi
  done < "$BASE_ENV"
else
  fatal "Missing base.env at $BASE_ENV"
fi




# ============================================================
# Apply TYPE layer
# ============================================================

TYPE_DIR="/opt/mc/${TYPE}"

if [[ ! -d "$TYPE_DIR" ]]; then
  fatal "TYPE directory missing: ${TYPE_DIR}"
fi

log INFO "Applying TYPE layer: ${TYPE}"
retry 3 1 cp -r "$TYPE_DIR"/* /data


# ============================================================
# Optional S3 sync
# ============================================================

if [[ "${S3_SYNC_ENABLED:-false}" == "true" ]]; then
  log INFO "Running S3 sync..."
  retry 5 3 bash "$SYNC_S3"
fi


# ============================================================
# Download / detect server.jar
# ============================================================

log INFO "Resolving server.jar (TYPE=${TYPE})"

case "$TYPE" in
  vanilla)    bash "$DL_VANILLA" ;;
  fabric)     bash "$DL_FABRIC" ;;
  forge)      bash "$DL_FORGE" ;;
  neoforge)   bash "$DL_NEOFORGE" ;;
  paper)      bash "$DL_PAPER" ;;
  purpur)     bash "$DL_PURPUR" ;;
  velocity)   bash "$DL_VELOCITY" ;;
  waterfall)  bash "$DL_WATERFALL" ;;
  bungeecord) bash "$DL_BUNGEECORD" ;;
  *)
    fatal "Unknown TYPE=${TYPE}"
    ;;
esac

[[ -f /data/server.jar ]] || fatal "server.jar missing after download"


# ============================================================
# Generate TYPE-specific configs (paper/purpur/bungee/velocity etc)
# ============================================================

log INFO "Generating TYPE configs..."
bash "$TYPE_CONFIG"


# ============================================================
# Generate server.properties
# ============================================================

log INFO "Generating server.properties..."
bash /opt/mc/scripts/generate_server_properties.sh


# ============================================================
# Build JVM / MC args
# ============================================================

log INFO "Building JVM / MC args..."
bash "$MAKE_ARGS"


# ============================================================
# Launch server
# ============================================================

log START "Launching Minecraft Server..."
exec java $(cat /data/jvm.args) -jar /data/server.jar $(cat /data/mc.args)

fatal "Java exited unexpectedly"
