#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$1] $2"
}

JVM_ARGS_FILE="/data/jvm.args"

# ------------------------------------------------------------
# Skip if jvm.args already exists
# ------------------------------------------------------------
if [[ -f "$JVM_ARGS_FILE" ]]; then
  log INFO "jvm.args already exists, skipping auto-generation"
  exit 0
fi

log INFO "Generating default jvm.args"

# ------------------------------------------------------------
# Defaults
# ------------------------------------------------------------
: "${MAX_MEMORY:=2G}"
: "${MIN_MEMORY:=$MAX_MEMORY}"

JAVA_MAJOR="${JAVA_VERSION:-21}"

# ------------------------------------------------------------
# Base JVM options
# ------------------------------------------------------------
cat > "$JVM_ARGS_FILE" <<EOF
-Xms${MIN_MEMORY}
-Xmx${MAX_MEMORY}

# --- Encoding ---
-Dfile.encoding=UTF-8
-Dsun.stdout.encoding=UTF-8
-Dsun.stderr.encoding=UTF-8

# --- Performance ---
-XX:+UseG1GC
-XX:+ParallelRefProcEnabled
-XX:MaxGCPauseMillis=200
-XX:+UnlockExperimentalVMOptions
-XX:+DisableExplicitGC
-XX:+AlwaysPreTouch
-XX:G1NewSizePercent=30
-XX:G1MaxNewSizePercent=40
-XX:G1HeapRegionSize=16M
-XX:G1ReservePercent=20
-XX:G1HeapWastePercent=5
-XX:G1MixedGCCountTarget=4
-XX:InitiatingHeapOccupancyPercent=15
-XX:G1MixedGCLiveThresholdPercent=90
-XX:G1RSetUpdatingPauseTimePercent=5
-XX:SurvivorRatio=32
-XX:+PerfDisableSharedMem

# --- Networking ---
-Djava.net.preferIPv4Stack=true

EOF

# ------------------------------------------------------------
# Java 21+ specific flags
# ------------------------------------------------------------
if [[ "$JAVA_MAJOR" -ge 21 ]]; then
  cat >> "$JVM_ARGS_FILE" <<EOF
# --- Java 21+ ---
-XX:+UseStringDeduplication
EOF
fi

# ------------------------------------------------------------
# C2ME / OpenCL safe flags (no hard enable)
# ------------------------------------------------------------
cat >> "$JVM_ARGS_FILE" <<EOF
# --- C2ME / GPU safe ---
-Dc2me.opts.chunkio=true
-Dc2me.opts.scheduling=true
EOF

chmod 644 "$JVM_ARGS_FILE"

log INFO "jvm.args generated successfully"
