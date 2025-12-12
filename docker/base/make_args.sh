#!/bin/bash
set -euo pipefail

log() { echo "[make_args] $*"; }

DATA_DIR="/data"

JVM_OUT="${DATA_DIR}/jvm.args"
MC_OUT="${DATA_DIR}/mc.args"

TYPE_LOWER="$(echo "${TYPE:-vanilla}" | tr '[:upper:]' '[:lower:]')"

# ------------------------------------------------------------
# Docker イメージ → JAVA_VERSION 必ず存在させる
# ------------------------------------------------------------
JAVA_VERSION="${JAVA_VERSION:-25}"

# Memory settings
MAX_MEMORY="${MAX_MEMORY:-4G}"
INIT_MEMORY="${INIT_MEMORY:-${MAX_MEMORY}}"

# ------------------------------------------------------------
# JVM ARG BUILDER
# ------------------------------------------------------------

build_jvm_args() {
  log "Building JVM arguments..."

  : > "$JVM_OUT"

  echo "-Xms${INIT_MEMORY}" >> "$JVM_OUT"
  echo "-Xmx${MAX_MEMORY}" >> "$JVM_OUT"

  # Java 21 以上の GC + 最適化
  if [[ "$JAVA_VERSION" -ge 21 ]]; then
    echo "-XX:+UseG1GC" >> "$JVM_OUT"
    echo "-XX:+AlwaysPreTouch" >> "$JVM_OUT"
    echo "-XX:+UseStringDeduplication" >> "$JVM_OUT"
  fi

  # Native access (Fabric/C2ME GPU 用)
  echo "--enable-native-access=ALL-UNNAMED" >> "$JVM_OUT"

  # User override
  [[ -f "${DATA_DIR}/jvm.override" ]] && cat "${DATA_DIR}/jvm.override" >> "$JVM_OUT"

  log "JVM args built."
}

# ------------------------------------------------------------
# MC ARG BUILDER
# ------------------------------------------------------------

build_mc_args() {
  log "Building Minecraft arguments..."

  : > "$MC_OUT"

  echo "--nogui" >> "$MC_OUT"

  case "$TYPE_LOWER" in
    fabric) ;;
    forge) ;;
    neoforge) ;;
    paper) ;;
    purpur) ;;  
    velocity) ;;
    waterfall) ;;
    bungeecord) ;;
    vanilla) ;;
    *)
      log "Unknown TYPE=${TYPE_LOWER}, using vanilla args"
      ;;
  esac

  [[ -f "${DATA_DIR}/mc.override" ]] && cat "${DATA_DIR}/mc.override" >> "$MC_OUT"

  log "MC args built."
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

build_jvm_args
build_mc_args

log "make_args.sh completed successfully."
