#!/bin/bash
set -euo pipefail

# ============================================================
#  Fast S3 Sync (parallel + checksum aware)
# ============================================================

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  echo "[$(timestamp)] [S3] $1"
}

S3_BUCKET="${S3_BUCKET:?S3_BUCKET required}"
S3_PREFIX="${S3_PREFIX:-mods}"
S3_ENDPOINT="${S3_ENDPOINT:?S3_ENDPOINT required}"
S3_ACCESS="${S3_ACCESS_KEY:?S3_ACCESS_KEY required}"
S3_SECRET="${S3_SECRET_KEY:?S3_SECRET_KEY required}"

LOCAL_MODS="/data/mods"
LOCAL_CONFIG="/data/config"

mc alias set sync "$S3_ENDPOINT" "$S3_ACCESS" "$S3_SECRET" >/dev/null

mkdir -p "$LOCAL_MODS" "$LOCAL_CONFIG"

# ============================================================
# 1. Get remote file list (mods + config)
# ============================================================
log "Fetching remote file list..."

REMOTE_LIST=$(mc ls --recursive "sync/${S3_BUCKET}/${S3_PREFIX}" | awk '{print $6}')
REMOTE_DIR="sync/${S3_BUCKET}/${S3_PREFIX}"

# ============================================================
# 2. Local list
# ============================================================
LOCAL_LIST=$(find "$LOCAL_MODS" -type f -printf "%f\n")

# ============================================================
# 3. Determine which files need to be updated
# ============================================================
FILES_TO_DOWNLOAD=()
FILES_TO_DELETE=()

log "Comparing checksums..."

for remote in $REMOTE_LIST; do
  base=$(basename "$remote")
  remote_sha=$(mc stat "sync/${S3_BUCKET}/${S3_PREFIX}/${base}" | awk '/ETag/ {gsub("\"","");print $2}')

  if [[ -f "$LOCAL_MODS/$base" ]]; then
    local_sha=$(sha1sum "$LOCAL_MODS/$base" | awk '{print $1}')
    if [[ "$local_sha" == "$remote_sha" ]]; then
      continue
    fi
  fi

  FILES_TO_DOWNLOAD+=("$base")
done

for local in $LOCAL_LIST; do
  if ! echo "$REMOTE_LIST" | grep -q "$local"; then
    FILES_TO_DELETE+=("$local")
  fi
done

log "Need to download: ${#FILES_TO_DOWNLOAD[@]}"
log "Need to delete:   ${#FILES_TO_DELETE[@]}"

# ============================================================
# 4. Parallel download
# ============================================================

download_file() {
  local file="$1"
  mc cp "${REMOTE_DIR}/${file}" "$LOCAL_MODS/${file}" >/dev/null \
    && log "Downloaded: $file" \
    || log "ERROR downloading: $file"
}

export -f download_file
export REMOTE_DIR
export LOCAL_MODS

log "Starting parallel downloads..."
printf "%s\n" "${FILES_TO_DOWNLOAD[@]}" | xargs -n1 -P8 -I{} bash -c 'download_file "$@"' _ {}

# ============================================================
# 5. Delete files no longer in S3
# ============================================================
for del in "${FILES_TO_DELETE[@]}"; do
  rm -f "$LOCAL_MODS/$del"
  log "Deleted: $del"
done

log "S3 sync completed successfully"
