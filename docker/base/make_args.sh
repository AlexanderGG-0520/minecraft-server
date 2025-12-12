#!/bin/bash
set -euo pipefail

log() { echo "[make_args] $*"; }

DATA_DIR="/data"

JVM_OUT="${DATA_DIR}/jvm.args"
MC_OUT="${DATA_DIR}/mc.args"

TYPE_LOWER="$(echo "${TYPE}" | tr '[:upper:]' '[:lower:]')"

# ============================================================
# JVM ARG BUILDER
# ============================================================

build_jvm_args() {
  log "Building JVM arguments..."

  # Always start fresh
  : > "$JVM_OUT"

  # Memory
  if [[ -n "${MAX_MEMORY:-}" ]]; then
    echo "-Xms${MAX_MEMORY}" >> "$JVM_OUT"
    echo "-Xmx${MAX_MEMORY}" >> "$JVM_OUT"
  else
    echo "-Xmx4G" >> "$JVM_OUT"
  fi

  # GC
  if [[ "${JAVA_VERSION:-25}" -ge 21 ]]; then
    echo "-XX:+UseG1GC" >> "$JVM_OUT"
    echo "-XX:+AlwaysPreTouch" >> "$JVM_OUT"
    echo "-XX:+UseStringDeduplication" >> "$JVM_OUT"
  fi

  # GPU configs
  echo "--enable-native-access=ALL-UNNAMED" >> "$JVM_OUT"

  # Allow user overrides
  [[ -f "${DATA_DIR}/jvm.override" ]] && cat "${DATA_DIR}/jvm.override" >> "$JVM_OUT"

  log "JVM args built."
}

# ============================================================
# MC ARG BUILDER
# ============================================================

build_mc_args() {
  log "Building Minecraft arguments..."

  : > "$MC_OUT"

  # Universal args
  echo "--nogui" >> "$MC_OUT"

  # TYPE-based customization
  case "$TYPE_LOWER" in

    fabric)
      echo "--launchTarget fabric-server" >> "$MC_OUT"
      ;;

    paper)
      echo "--paper" >> "$MC_OUT"
      ;;

    neoforge)
      echo "--launchTarget neoforge" >> "$MC_OUT"
      ;;

    forge)
      echo "--launchTarget forge" >> "$MC_OUT"
      ;;

    vanilla)
      # none
      ;;

    *)
      log "Unknown TYPE=$TYPE → using vanilla args"
      ;;
  esac

  # Allow override
  [[ -f "${DATA_DIR}/mc.override" ]] && cat "${DATA_DIR}/mc.override" >> "$MC_OUT"

  log "MC args built."
}

# ============================================================
# Main
# ============================================================

build_jvm_args
build_mc_args

log "make_args.sh completed successfully."
