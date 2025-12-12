#!/usr/bin/env bash
set -euo pipefail

cd /data

log "World reset triggered."

# 対象ディレクトリ（柔軟に拡張可能）
TARGETS=(
  "world"
  "world_nether"
  "world_the_end"
  "world*"
  "DIM1"
  "DIM-1"
  "dimensions"
)

for t in "${TARGETS[@]}"; do
  if compgen -G "${t}" > /dev/null; then
    log "Removing: ${t}"
    rm -rf ${t} || log "Warning: failed to remove ${t}"
  fi
done

# プレイヤーデータなど、必要なら削除も可能（オプション）
if [[ "${RESET_PLAYERDATA:-false}" == "true" ]]; then
  log "Removing playerdata"
  rm -rf playerdata || true
fi

# flag removal
rm -f reset-world.flag || true

log "World reset complete."
