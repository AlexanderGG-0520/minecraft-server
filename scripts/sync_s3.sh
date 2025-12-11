#!/usr/bin/env bash
set -euo pipefail

log() { echo "[sync_s3] $*"; }

: "${MODS_S3_ENDPOINT:?MODS_S3_ENDPOINT is required}"
: "${MODS_S3_BUCKET:?MODS_S3_BUCKET is required}"
: "${MODS_S3_ACCESS_KEY:?MODS_S3_ACCESS_KEY is required}"
: "${MODS_S3_SECRET_KEY:?MODS_S3_SECRET_KEY is required}"

ALIAS="storage"
PREFIX="${MODS_S3_PREFIX:-}"

REMOTE="${ALIAS}/${MODS_S3_BUCKET}/${PREFIX}"

# 再試行関数
retry() {
  local n=0
  local try=5
  until "$@"; do
    if (( n < try )); then
      ((n++))
      log "Retry $n/$try…"
      sleep 2
    else
      log "ERROR: command failed after ${try} attempts."
      return 1
    fi
  done
}

# MinIO alias 設定
retry mc alias set "${ALIAS}" "${MODS_S3_ENDPOINT}" \
  "${MODS_S3_ACCESS_KEY}" "${MODS_S3_SECRET_KEY}"

mkdir -p /data/mods /data/config

if [[ "${SYNC_MODS_ONLY:-false}" != "true" ]]; then
  log "Syncing config/ → /data/config/"
  retry mc mirror --overwrite "${REMOTE}/config/" /data/config/ \
    || log "WARN: config sync failed (ignored)"
fi

if [[ "${SYNC_CONFIG_ONLY:-false}" != "true" ]]; then
  log "Syncing mods/ → /data/mods/"
  retry mc mirror --overwrite "${REMOTE}/mods/" /data/mods/ \
    || log "WARN: mods sync failed (ignored)"
fi

# 不要MOD削除（ユーザー要望）
if [[ "${CLEAN_UNUSED_MODS:-false}" == "true" ]]; then
  log "Cleaning unused mods (mirror --remove)"
  retry mc mirror --overwrite --remove "${REMOTE}/mods/" /data/mods/
fi

# 権限整理
log "Fixing permissions"
chown -R mc:mc /data/mods /data/config || true

log "S3 sync completed successfully."
