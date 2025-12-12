#!/bin/bash
set -euo pipefail

# ============================================================
# Safe S3 sync wrapper
# ============================================================

sync_s3_main() {

  # -----------------------------------------
  # 1. S3_SYNC_ENABLED=false → 全スキップ
  # -----------------------------------------
  if [[ "${S3_SYNC_ENABLED:-false}" != "true" ]]; then
    echo "[S3] Sync disabled. Skipping."
    return 0
  fi

  # -----------------------------------------
  # 2. 必須パラメータチェック
  # -----------------------------------------
  : "${S3_ENDPOINT:?S3_ENDPOINT required}"
  : "${S3_BUCKET:?S3_BUCKET required}"
  : "${S3_ACCESS_KEY:?S3_ACCESS_KEY required}"
  : "${S3_SECRET_KEY:?S3_SECRET_KEY required}"

  # -----------------------------------------
  # 3. MinIO Client Config
  # -----------------------------------------
  mc alias set minio "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY"

  echo "[S3] Downloading mods..."
  mc mirror --overwrite --remove "minio/${S3_BUCKET}/mods/"   /data/mods/

  echo "[S3] Downloading configs..."
  mc mirror --overwrite --remove "minio/${S3_BUCKET}/config/" /data/config/

  echo "[S3] Sync Completed!"
}
