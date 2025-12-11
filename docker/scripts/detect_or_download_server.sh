#!/bin/bash

set -euo pipefail

# ============================================================
# server.jar Download Manager (Fast, Cached, TYPE-aware)
# ============================================================

JAR_PATH="/data/server.jar"
META_PATH="/data/server.jar.meta"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  echo "[$(timestamp)] [DOWNLOAD] $1"
}

# ============================================================
# 1. Determine download URL based on TYPE + VERSION
# ============================================================

resolve_download_url() {
  case "$TYPE" in

    fabric)
      # Example: https://meta.fabricmc.net/v2/versions/loader/1.21.4/0.16.9/1.0.1/server/jar
      local loader_version=$(curl -s https://meta.fabricmc.net/v2/versions/loader | jq -r '.[0].version')
      local installer_version=$(curl -s https://meta.fabricmc.net/v2/versions/installer | jq -r '.[0].version')
      echo "https://meta.fabricmc.net/v2/versions/loader/${VERSION}/${loader_version}/${installer_version}/server/jar"
      ;;

    paper)
      # Example: https://api.papermc.io/v2/projects/paper/versions/1.21.4/builds/350/downloads/paper-1.21.4-350.jar
      local latest_build=$(curl -s https://api.papermc.io/v2/projects/paper/versions/${VERSION} | jq -r '.builds[-1]')
      echo "https://api.papermc.io/v2/projects/paper/versions/${VERSION}/builds/${latest_build}/downloads/paper-${VERSION}-${latest_build}.jar"
      ;;

    forge)
      # Forge: Query maven metadata
      echo "https://maven.minecraftforge.net/net/minecraftforge/forge/${VERSION}/forge-${VERSION}-server.jar"
      ;;

    neoforge)
      # NeoForge: official maven
      echo "https://maven.neoforged.net/releases/net/neoforged/forge/${VERSION}/forge-${VERSION}-server.jar"
      ;;

    vanilla)
      echo "https://launcher.mojang.com/v1/objects/$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r --arg v "$VERSION" '.versions[] | select(.id==$v) | .url' | xargs curl -s | jq -r '.downloads.server.sha1')/server.jar"
      ;;

    proxy)
      # Velocity example
      local vinfo=$(curl -s https://api.papermc.io/v2/projects/velocity)
      local latest=$(echo "$vinfo" | jq -r '.versions[-1]')
      local build=$(curl -s https://api.papermc.io/v2/projects/velocity/versions/${latest} | jq -r '.builds[-1]')
      echo "https://api.papermc.io/v2/projects/velocity/versions/${latest}/builds/${build}/downloads/velocity-${latest}-${build}.jar"
      ;;

    *)
      log "Unsupported TYPE: ${TYPE}"
      exit 1
      ;;
  esac
}

# ============================================================
# 2. Compare SHA1 for caching
# ============================================================

download_if_needed() {
  local url="$1"

  log "Resolved URL: $url"

  # Fetch remote SHA1 if available
  local remote_sha=$(curl -sI "$url" | awk '/ETag/ {gsub("\"","");print $2}')
  [[ -z "$remote_sha" ]] && remote_sha="unknown"

  # Check local meta cache
  if [[ -f "$META_PATH" ]]; then
    local local_sha=$(cat "$META_PATH")
    if [[ "$local_sha" == "$remote_sha" && -f "$JAR_PATH" ]]; then
      log "server.jar is up to date (ETag match)"
      return 0
    fi
  fi

  # Download
  log "Downloading server.jar..."
  curl -L --fail --retry 5 --retry-delay 3 -o "$JAR_PATH.tmp" "$url"

  mv "$JAR_PATH.tmp" "$JAR_PATH"
  echo "$remote_sha" > "$META_PATH"
  log "server.jar updated"
}

# ============================================================
# Main Entry
# ============================================================
main() {
  local url
  url=$(resolve_download_url)
  download_if_needed "$url"
}

main
