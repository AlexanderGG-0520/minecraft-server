#!/usr/bin/env bash
set -euo pipefail

log() { echo "[bungeecord] $*"; }

DATA_DIR="/data"
JAR="${DATA_DIR}/server.jar"
TMP_JAR="/tmp/bungeecord_latest.jar"

# BungeeCord ダウンロード URL
# Jenkins → PaperMC が管理。最新版の安定ビルド jar をそのまま取得。
BC_URL="https://ci.md-5.net/job/BungeeCord/lastStableBuild/artifact/bootstrap/target/BungeeCord.jar"

log "Checking existing server.jar..."

# 既に JAR が存在する場合はスキップ（強制上書きしない）
if [[ -f "${JAR}" ]]; then
  log "Existing server.jar found – skipping download."
  exit 0
fi

log "Downloading latest BungeeCord from: ${BC_URL}"

# ダウンロード（最大3回 retry）
attempt=0
max_attempts=3
until curl -fsSL "${BC_URL}" -o "${TMP_JAR}"; do
  attempt=$((attempt+1))
  if [[ $attempt -ge $max_attempts ]]; then
    log "Download failed after ${max_attempts} attempts."
    exit 1
  fi
  log "Download failed – retrying (${attempt}/${max_attempts})..."
  sleep 2
done

# 保存
mv "${TMP_JAR}" "${JAR}"

log "BungeeCord downloaded successfully → ${JAR}"
exit 0
