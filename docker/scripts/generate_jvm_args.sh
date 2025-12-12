#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$1] $2"
}

JVM_ARGS_FILE="/data/jvm.args"

if [[ -f "$JVM_ARGS_FILE" ]]; then
  log INFO "jvm.args already exists, skipping auto-generation"
  exit 0
fi

log INFO "Generating default jvm.args"

: "${MAX_MEMORY:=2G}"
: "${MIN_MEMORY:=$MAX_MEMORY}"
: "${JAVA_VERSION:=21}"

cat > "$JVM_ARGS_FILE" <<EOF
-Xms${MIN_MEMORY}
-Xmx${MAX_MEMORY}
-Dfile.encoding=UTF-8
-Dsun.stdout.encoding=UTF-8
-Dsun.stderr.encoding=UTF-8
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
-Djava.net.preferIPv4Stack=true
-Dc2me.opts.chunkio=true
-Dc2me.opts.scheduling=true
EOF

if [[ "$JAVA_VERSION" -ge 21 ]]; then
  echo "-XX:+UseStringDeduplication" >> "$JVM_ARGS_FILE"
fi

chmod 644 "$JVM_ARGS_FILE"
log INFO "jvm.args generated successfully"
