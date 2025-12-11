#!/usr/bin/env bash
set -euo pipefail

# detect_or_download_server.sh
# TYPE / VERSION を見て server.jar を /data に用意する

TYPE="${1:-${TYPE:-fabric}}"
VERSION_REQ="${2:-${VERSION:-latest}}"

cd /data

log() { echo "[detect] $*"; }

curl_json() {
  # curl で JSON を取るラッパ
  curl -fsSL "$@"
}

download_to_server_jar() {
  local url="$1"
  log "Downloading server.jar from: ${url}"
  curl -fsSL "${url}" -o server.jar
  chmod 644 server.jar
  log "server.jar downloaded."
}

# ===================== Vanilla =====================
install_vanilla() {
  log "Installing Vanilla server (VERSION=${VERSION_REQ})"

  local manifest url version_id version_json server_url

  manifest="$(curl_json https://piston-meta.mojang.com/mc/game/version_manifest_v2.json)"

  if [[ "${VERSION_REQ}" == "latest" ]]; then
    version_id="$(echo "${manifest}" | jq -r '.latest.release')"
  else
    version_id="${VERSION_REQ}"
  fi

  url="$(echo "${manifest}" | jq -r --arg id "${version_id}" '.versions[] | select(.id == $id) | .url')"
  if [[ -z "${url}" || "${url}" == "null" ]]; then
    log "ERROR: Could not find version manifest for ${version_id}"
    exit 1
  fi

  version_json="$(curl_json "${url}")"
  server_url="$(echo "${version_json}" | jq -r '.downloads.server.url')"

  if [[ -z "${server_url}" || "${server_url}" == "null" ]]; then
    log "ERROR: No server download URL for Vanilla ${version_id}"
    exit 1
  fi

  download_to_server_jar "${server_url}"
}

# ===================== Fabric =====================
install_fabric() {
  log "Installing Fabric server (VERSION=${VERSION_REQ})"

  local game_version meta_game loader_entry loader_version installer_version

  # ゲームバージョン決定（latestならFabricがstable扱いしている最新版）
  if [[ "${VERSION_REQ}" == "latest" ]]; then
    meta_game="$(curl_json https://meta.fabricmc.net/v2/versions/game)"
    game_version="$(echo "${meta_game}" | jq -r 'map(select(.stable == true))[0].version')"
  else
    game_version="${VERSION_REQ}"
  fi

  if [[ -z "${game_version}" || "${game_version}" == "null" ]]; then
    log "ERROR: Could not resolve Fabric game version from VERSION=${VERSION_REQ}"
    exit 1
  fi

  log "Resolved Fabric game version: ${game_version}"

  # loader + installer の最新版をまとめて取得
  loader_entry="$(curl_json "https://meta.fabricmc.net/v2/versions/loader/${game_version}" | jq '.[0]')"

  loader_version="$(echo "${loader_entry}" | jq -r '.loader.version')"
  installer_version="$(echo "${loader_entry}" | jq -r '.installer.version')"

  if [[ -z "${loader_version}" || "${loader_version}" == "null" ]]; then
    log "ERROR: Could not resolve Fabric loader version"
    exit 1
  fi
  if [[ -z "${installer_version}" || "${installer_version}" == "null" ]]; then
    log "ERROR: Could not resolve Fabric installer version"
    exit 1
  fi

  log "Using Fabric loader=${loader_version}, installer=${installer_version}"

  local url
  url="https://meta.fabricmc.net/v2/versions/loader/${game_version}/${loader_version}/${installer_version}/server/jar"
  download_to_server_jar "${url}"
}

# ===================== Quilt =====================
install_quilt() {
  log "Installing Quilt server (VERSION=${VERSION_REQ})"
  # Quilt API は Fabric に似ているが、詳細な仕様は公式ドキュメントを要確認。
  # ここでは best-effort 実装＋将来の上書き用 ENV を提供しておく。

  if [[ -n "${QUILT_SERVER_URL:-}" ]]; then
    download_to_server_jar "${QUILT_SERVER_URL}"
    return
  fi

  log "ERROR: Quilt auto-install is not fully implemented yet. Set QUILT_SERVER_URL."
  exit 1
}

# ===================== Paper family via PaperMC API =====================
# paper / folia / velocity / waterfall
install_papermc_project() {
  local project="$1"    # paper / folia / velocity / waterfall
  local version_req="$2"
  local meta versions_json builds_json version build jar_name url

  log "Installing ${project} (VERSION=${version_req})"

  meta="$(curl_json "https://api.papermc.io/v2/projects/${project}")"

  if [[ "${version_req}" == "latest" ]]; then
    version="$(echo "${meta}" | jq -r '.versions[-1]')"
  else
    version="${version_req}"
  fi

  if [[ -z "${version}" || "${version}" == "null" ]]; then
    log "ERROR: Could not resolve ${project} version from VERSION=${version_req}"
    exit 1
  fi

  builds_json="$(curl_json "https://api.papermc.io/v2/projects/${project}/versions/${version}")"
  build="$(echo "${builds_json}" | jq -r '.builds[-1]')"

  if [[ -z "${build}" || "${build}" == "null" ]]; then
    log "ERROR: Could not resolve ${project} build for version=${version}"
    exit 1
  fi

  local build_info
  build_info="$(curl_json "https://api.papermc.io/v2/projects/${project}/versions/${version}/builds/${build}")"
  jar_name="$(echo "${build_info}" | jq -r '.downloads.application.name')"

  if [[ -z "${jar_name}" || "${jar_name}" == "null" ]]; then
    log "ERROR: Could not get jar name for ${project} ${version}-${build}"
    exit 1
  fi

  url="https://api.papermc.io/v2/projects/${project}/versions/${version}/builds/${build}/downloads/${jar_name}"
  download_to_server_jar "${url}"
}

install_paper()    { install_papermc_project "paper"    "${VERSION_REQ}"; }
install_folia()    { install_papermc_project "folia"    "${VERSION_REQ}"; }
install_velocity() { install_papermc_project "velocity" "${VERSION_REQ}"; }
install_waterfall(){ install_papermc_project "waterfall" "${VERSION_REQ}"; }

# ===================== Purpur =====================
install_purpur() {
  log "Installing Purpur (VERSION=${VERSION_REQ})"

  local version_req="$1"
  local version json url

  if [[ "${version_req}" == "latest" ]]; then
    json="$(curl_json https://api.purpurmc.org/v2/purpur)"
    version="$(echo "${json}" | jq -r '.versions[-1]')"
  else
    version="${version_req}"
  fi

  if [[ -z "${version}" || "${version}" == "null" ]]; then
    log "ERROR: Could not resolve Purpur version"
    exit 1
  fi

  # Purpur は latest build download を直接提供
  url="https://api.purpurmc.org/v2/purpur/${version}/latest/download"
  download_to_server_jar "${url}"
}

# ===================== Forge =====================
install_forge() {
  log "Installing Forge server"

  # Forge は公式APIが扱いにくいので、バージョン指定を必須にする
  if [[ -n "${FORGE_INSTALLER_URL:-}" ]]; then
    log "Using FORGE_INSTALLER_URL"
    curl -fsSL "${FORGE_INSTALLER_URL}" -o forge-installer.jar
  else
    if [[ -z "${FORGE_VERSION:-}" ]]; then
      log "ERROR: FORGE_VERSION or FORGE_INSTALLER_URL must be set for TYPE=forge"
      exit 1
    fi
    # 例: FORGE_VERSION=1.20.1-47.1.0
    local v="${FORGE_VERSION}"
    local url="https://maven.minecraftforge.net/net/minecraftforge/forge/${v}/forge-${v}-installer.jar"
    log "Downloading Forge installer from ${url}"
    curl -fsSL "${url}" -o forge-installer.jar || {
      log "ERROR: Failed to download Forge installer. Check FORGE_VERSION."
      exit 1
    }
  fi

  log "Running Forge installer (server)"
  java -jar forge-installer.jar --installServer || {
    log "ERROR: Forge installer failed"
    exit 1
  }

  # Forge は基本的にランチャースクリプトか forge-xxx.jar を作る
  if [[ -f "forge-${FORGE_VERSION:-}.jar" ]]; then
    mv "forge-${FORGE_VERSION}.jar" server.jar
  elif compgen -G "forge-*-server.jar" > /dev/null; then
    # もっと雑に拾う fallback
    mv forge-*-server.jar server.jar
  fi

  if [[ ! -f server.jar ]]; then
    log "ERROR: Could not locate installed Forge server jar"
    exit 1
  fi

  rm -f forge-installer.jar
  log "Forge server.jar ready."
}

# ===================== NeoForge =====================
install_neoforge() {
  log "Installing NeoForge server"

  if [[ -n "${NEOFORGE_INSTALLER_URL:-}" ]]; then
    curl -fsSL "${NEOFORGE_INSTALLER_URL}" -o neoforge-installer.jar
  else
    if [[ -z "${NEOFORGE_VERSION:-}" ]]; then
      log "ERROR: NEOFORGE_VERSION or NEOFORGE_INSTALLER_URL must be set for TYPE=neoforge"
      exit 1
    fi
    local v="${NEOFORGE_VERSION}"
    local url="https://maven.neoforged.net/releases/net/neoforged/forge/${v}/forge-${v}-installer.jar"
    log "Downloading NeoForge installer from ${url}"
    curl -fsSL "${url}" -o neoforge-installer.jar || {
      log "ERROR: Failed to download NeoForge installer. Check NEOFORGE_VERSION."
      exit 1
    }
  fi

  log "Running NeoForge installer (server)"
  java -jar neoforge-installer.jar --installServer || {
    log "ERROR: NeoForge installer failed"
    exit 1
  }

  if compgen -G "forge-*-server.jar" > /dev/null; then
    mv forge-*-server.jar server.jar
  fi

  if [[ ! -f server.jar ]]; then
    log "ERROR: Could not locate installed NeoForge server jar"
    exit 1
  fi

  rm -f neoforge-installer.jar
  log "NeoForge server.jar ready."
}

# ===================== Glowstone =====================
install_glowstone() {
  log "Installing Glowstone"

  if [[ -n "${GLOWSTONE_SERVER_URL:-}" ]]; then
    download_to_server_jar "${GLOWSTONE_SERVER_URL}"
    return
  fi

  # GitHub releases の latest ダウンロード（将来変わる可能性あり）
  local url="https://github.com/GlowstoneMC/Glowstone/releases/latest/download/glowstone.jar"
  download_to_server_jar "${url}"
}

# ===================== Cuberite =====================
install_cuberite() {
  log "Installing Cuberite"

  if [[ -z "${CUBERITE_SERVER_URL:-}" ]]; then
    log "ERROR: CUBERITE_SERVER_URL must be set for TYPE=cuberite"
    exit 1
  fi
  download_to_server_jar "${CUBERITE_SERVER_URL}"
}

# ===================== Mohist / CatServer =====================
install_mohist() {
  log "Installing Mohist"

  if [[ -z "${MOHIST_SERVER_URL:-}" ]]; then
    log "ERROR: MOHIST_SERVER_URL must be set for TYPE=mohist"
    exit 1
  fi
  download_to_server_jar "${MOHIST_SERVER_URL}"
}

install_catserver() {
  log "Installing CatServer"

  if [[ -z "${CATSERVER_SERVER_URL:-}" ]]; then
    log "ERROR: CATSERVER_SERVER_URL must be set for TYPE=catserver"
    exit 1
  fi
  download_to_server_jar "${CATSERVER_SERVER_URL}"
}

# ===================== Pufferfish / Airplane / Leaves =====================
# これらは配布場所が変わりがちなので、基本は URL 指定で運用。
install_pufferfish() {
  log "Installing Pufferfish"

  if [[ -z "${PUFFERFISH_SERVER_URL:-}" ]]; then
    log "ERROR: PUFFERFISH_SERVER_URL must be set for TYPE=pufferfish"
    exit 1
  fi
  download_to_server_jar "${PUFFERFISH_SERVER_URL}"
}

install_airplane() {
  log "Installing Airplane"
  if [[ -z "${AIRPLANE_SERVER_URL:-}" ]]; then
    log "ERROR: AIRPLANE_SERVER_URL must be set for TYPE=airplane"
    exit 1
  fi
  download_to_server_jar "${AIRPLANE_SERVER_URL}"
}

install_leaves() {
  log "Installing Leaves"
  if [[ -z "${LEAVES_SERVER_URL:-}" ]]; then
    log "ERROR: LEAVES_SERVER_URL must be set for TYPE=leaves"
    exit 1
  fi
  download_to_server_jar "${LEAVES_SERVER_URL}"
}

# ===================== Dispatcher =====================
log "TYPE=${TYPE}, VERSION_REQ=${VERSION_REQ}"

case "${TYPE}" in
  vanilla)      install_vanilla ;;
  fabric)       install_fabric ;;
  quilt)        install_quilt ;;
  paper)        install_paper ;;
  purpur)       install_purpur ;;
  folia)        install_folia ;;
  pufferfish)   install_pufferfish ;;
  airplane)     install_airplane ;;
  leaves)       install_leaves ;;
  forge)        install_forge ;;
  neoforge)     install_neoforge ;;
  mohist)       install_mohist ;;
  catserver)    install_catserver ;;
  velocity)     install_velocity ;;
  waterfall)    install_waterfall ;;
  bungeecord)
    log "Installing BungeeCord (CI build)"
    if [[ -n "${BUNGEECORD_SERVER_URL:-}" ]]; then
      download_to_server_jar "${BUNGEECORD_SERVER_URL}"
    else
      download_to_server_jar "https://ci.md-5.net/job/BungeeCord/lastSuccessfulBuild/artifact/bootstrap/target/BungeeCord.jar"
    fi
    ;;
  glowstone)    install_glowstone ;;
  cuberite)     install_cuberite ;;
  *)
    log "ERROR: Unsupported TYPE=${TYPE}"
    exit 1
    ;;
esac

if [[ ! -f server.jar ]]; then
  log "ERROR: server.jar was not created"
  exit 1
fi

log "Done. server.jar is ready."
