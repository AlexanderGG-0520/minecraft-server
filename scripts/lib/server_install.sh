# shellcheck shell=bash

download_file_atomic() {
  local url="$1"
  local dest="$2"
  local label="$3"
  local tmp="${dest}.tmp.$$"

  rm -f -- "$tmp"
  if ! curl -fL "$url" -o "$tmp"; then
    rm -f -- "$tmp"
    die "Failed to download ${label}"
  fi

  [[ -s "$tmp" ]] || {
    rm -f -- "$tmp"
    die "Downloaded ${label} is empty"
  }

  mv -f "$tmp" "$dest"
}

download_vanilla_server_atomic() {
  local url="$1"
  local sha1="$2"
  local dest="$3"
  local tmp="${dest}.tmp.$$"

  rm -f -- "$tmp"
  if ! curl -fL "$url" -o "$tmp"; then
    rm -f -- "$tmp"
    die "Failed to download vanilla server.jar"
  fi

  [[ -s "$tmp" ]] || {
    rm -f -- "$tmp"
    die "Downloaded vanilla server.jar is empty"
  }

  echo "${sha1}  ${tmp}" | sha1sum -c - >/dev/null || {
    rm -f -- "$tmp"
    die "Downloaded vanilla server.jar checksum mismatch"
  }

  mv -f "$tmp" "$dest"
}

install_vanilla_server_artifact() {
  [[ -n "${VERSION:-}" ]] || die "VERSION is required for vanilla"

  if [[ -f "${DATA_DIR}/server.jar" ]]; then
    assert_server_install_matches "server.jar" "vanilla" "${VERSION}"
    log INFO "server.jar already exists, skipping"
    return
  fi

  log INFO "Downloading vanilla server ${VERSION}"
  meta_url="$(curl -fsSL https://launchermeta.mojang.com/mc/game/version_manifest.json \
    | jq -r '.versions[] | select(.id=="'"${VERSION}"'") | .url')"
  [[ -n "${meta_url}" && "${meta_url}" != "null" ]] || die "Invalid VERSION: ${VERSION}"

  sha1="$(curl -fsSL "${meta_url}" | jq -r '.downloads.server.sha1')"
  download_vanilla_server_atomic \
    "https://piston-data.mojang.com/v1/objects/${sha1}/server.jar" \
    "${sha1}" \
    "${DATA_DIR}/server.jar"
  write_server_install_marker "server.jar" "vanilla" "${VERSION}"
}

install_fabric_server_artifact() {
  [[ -n "${VERSION:-}" ]] || die "VERSION is required for fabric"

  if [[ -f "${DATA_DIR}/fabric-server-launch.jar" ]]; then
    assert_server_install_matches "fabric-server-launch.jar" "fabric" "${VERSION}"
    log INFO "fabric-server-launch.jar already exists, skipping"
    return
  fi

  json="$(curl -fsSL "https://meta.fabricmc.net/v2/versions/loader/${VERSION}" || true)"

  LOADER_VERSION="$(printf '%s' "$json" | jq -er '
    if type=="array" and length>0 and .[0].loader.version
    then .[0].loader.version
    else empty
    end
  ')"

  [[ -n "${LOADER_VERSION}" ]] || die "Failed to resolve Fabric loader version"


  # ---- resolve installer (from Maven) ----
  INSTALLER_VERSION="${FABRIC_INSTALLER_VERSION:-latest}"
  if [[ "${INSTALLER_VERSION}" == "latest" ]]; then
    INSTALLER_VERSION="$(curl -fsSL \
      "https://maven.fabricmc.net/net/fabricmc/fabric-installer/maven-metadata.xml" \
      | tr -d '\r' \
      | grep -oPm1 '(?<=<latest>)[^<]+')" \
      || die "Failed to resolve Fabric installer version"
  fi

  log INFO "Installing Fabric server (MC=${VERSION}, loader=${LOADER_VERSION}, installer=${INSTALLER_VERSION})"

  curl -fL \
    "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${INSTALLER_VERSION}/fabric-installer-${INSTALLER_VERSION}.jar" \
    -o /tmp/fabric-installer.jar \
    || die "Failed to download Fabric installer"

  java -jar /tmp/fabric-installer.jar \
    server \
    -mcversion "${VERSION}" \
    -loader "${LOADER_VERSION}" \
    -downloadMinecraft \
    -dir "${DATA_DIR}" \
    || die "Fabric installer failed"

  log INFO "Fabric server.jar ready"
  write_server_install_marker "fabric-server-launch.jar" "fabric" "${VERSION}" "${LOADER_VERSION}"
}

install_quilt_server_artifact() {
  [[ -n "${VERSION:-}" ]] || die "VERSION is required for quilt"

  if [[ -f "${DATA_DIR}/server.jar" ]]; then
    assert_server_install_matches "server.jar" "quilt" "${VERSION}"
    log INFO "server.jar already exists, skipping"
    return
  fi

  log INFO "Installing Quilt server ${VERSION}"

  download_file_atomic \
    "https://meta.quiltmc.org/v3/versions/loader/${VERSION}/latest/server/jar" \
    "${DATA_DIR}/server.jar" \
    "Quilt server.jar"

  log INFO "Quilt server.jar ready"
  write_server_install_marker "server.jar" "quilt" "${VERSION}"
}

install_forge_server_artifact() {
  [[ -n "${VERSION:-}" ]] || die "VERSION is required for forge"

  FORGE_VER="${FORGE_VERSION:-latest}"
  FORGE_META_URL="https://files.minecraftforge.net/net/minecraftforge/forge/index_${VERSION}.html"

  # ---- resolve version FIRST ----
  if [[ "${FORGE_VER}" == "latest" ]]; then
    log INFO "Resolving latest Forge version for MC ${VERSION}"

    html="$(curl -fsSL "${FORGE_META_URL}" || true)"

    FORGE_VER="$(printf '%s' "$html" \
      | grep -oP 'forge-\K[0-9.]+' \
      | head -n 1)"

    [[ -n "${FORGE_VER}" ]] || {
      log ERROR "Failed to resolve Forge version. Response was:"
      log ERROR "$(echo "$html" | head -c 300)"
      die "Invalid Forge version"
    }
  fi

  # ---- sanity check ----
  [[ -n "${FORGE_VER}" && "${FORGE_VER}" != "null" ]] \
    || die "Invalid Forge version resolved: ${FORGE_VER}"

  MARKER="${DATA_DIR}/.installed-forge-${VERSION}-${FORGE_VER}"

  if [[ -f "${MARKER}" ]]; then
    assert_server_install_matches "run.sh" "forge" "${VERSION}"
    log INFO "Forge already installed (MC=${VERSION}, forge=${FORGE_VER}), skipping"
  else
    log INFO "Installing Forge server (MC=${VERSION}, forge=${FORGE_VER})"

    INSTALLER="forge-${VERSION}-${FORGE_VER}-installer.jar"
    curl -fL \
      "https://maven.minecraftforge.net/net/minecraftforge/forge/${VERSION}-${FORGE_VER}/${INSTALLER}" \
      -o "/tmp/${INSTALLER}" \
      || die "Failed to download Forge installer"

    java -jar "/tmp/${INSTALLER}" --installServer "${DATA_DIR}" \
      || die "Forge installer failed"

    [[ -x "${DATA_DIR}/run.sh" ]] || die "Forge install finished but run.sh not found"

    touch "${MARKER}"
    write_server_install_marker "run.sh" "forge" "${VERSION}" "${FORGE_VER}"
    log INFO "Forge installed marker created: ${MARKER}"
  fi
}

install_neoforge_server_artifact() {
  [[ -n "${VERSION:-}" ]] || die "VERSION is required for neoforge"

  NEO_VER="${NEOFORGE_VERSION:-latest}"
  META_URL="https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge"

  if [[ -z "$NEO_VER" || "$NEO_VER" == "latest" ]]; then
    log INFO "Resolving latest NeoForge (non-craftmine only)"
    json="$(curl -fsSL "$META_URL")"

    NEO_VER="$(
      printf '%s' "$json" | jq -r '
        .versions[]
        | select(test("craftmine") | not)
        | select(test("^21\\.1\\."))
      ' | head -n 1
    )"
  fi

  MARKER="${DATA_DIR}/.installed-neoforge-${VERSION}-${NEO_VER}"

  if [[ -f "${MARKER}" ]]; then
    assert_server_install_matches "run.sh" "neoforge" "${VERSION}"
    log INFO "NeoForge already installed (MC=${VERSION}, neoforge=${NEO_VER}), skipping"
  else
    log INFO "Installing NeoForge server (MC=${VERSION}, neoforge=${NEO_VER})"

    INSTALLER="neoforge-${NEO_VER}-installer.jar"
    curl -fL \
      "https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEO_VER}/${INSTALLER}" \
      -o "/tmp/${INSTALLER}" \
      || die "Failed to download NeoForge installer"

    java -jar "/tmp/${INSTALLER}" --installServer "${DATA_DIR}" \
      || die "NeoForge installer failed"

    [[ -x "${DATA_DIR}/run.sh" ]] || die "NeoForge install finished but run.sh not found"

    touch "${MARKER}"
    write_server_install_marker "run.sh" "neoforge" "${VERSION}" "${NEO_VER}"
    log INFO "NeoForge installed marker created: ${MARKER}"
  fi
}

install_paper_server_artifact() {
  [[ -n "${VERSION:-}" ]] || die "VERSION is required for paper"

  if [[ -f "${DATA_DIR}/server.jar" ]]; then
    assert_server_install_matches "server.jar" "paper" "${VERSION}"
    log INFO "server.jar already exists, skipping"
    return
  fi

  BUILD="${PAPER_BUILD:-latest}"

  log INFO "Installing Paper server (MC=${VERSION}, build=${BUILD})"

  if [[ "${BUILD}" == "latest" ]]; then
    log INFO "Resolving latest Paper build for MC ${VERSION}"

    json="$(curl -fsSL \
      "https://api.papermc.io/v2/projects/paper/versions/${VERSION}" || true)"

    BUILD="$(printf '%s' "$json" | jq -er '
      if has("builds")
        and (.builds|type=="array")
        and (.builds|length>0)
      then .builds[-1]
      else empty
      end
    ')"

    [[ -n "${BUILD}" ]] || {
      log ERROR "Failed to resolve Paper build. Response was:"
      log ERROR "$(echo "$json" | head -c 300)"
      die "Invalid Paper build"
    }
  fi

  JAR_NAME="paper-${VERSION}-${BUILD}.jar"

  download_file_atomic \
    "https://api.papermc.io/v2/projects/paper/versions/${VERSION}/builds/${BUILD}/downloads/${JAR_NAME}" \
    "${DATA_DIR}/server.jar" \
    "Paper server.jar"

  log INFO "Paper server.jar ready"
  write_server_install_marker "server.jar" "paper" "${VERSION}" "${BUILD}"
}

install_purpur_server_artifact() {
  [[ -n "${VERSION:-}" ]] || die "VERSION is required for purpur"

  if [[ -f "${DATA_DIR}/server.jar" ]]; then
    assert_server_install_matches "server.jar" "purpur" "${VERSION}"
    log INFO "server.jar already exists, skipping"
    return
  fi

  BUILD="${PURPUR_BUILD:-latest}"

  if [[ "${BUILD}" == "latest" ]]; then
    log INFO "Resolving latest Purpur build for MC ${VERSION}"

    json="$(curl -fsSL "https://api.purpurmc.org/v2/purpur/${VERSION}" || true)"

    BUILD="$(printf '%s' "$json" | jq -er '
      if has("builds")
        and (.builds|type=="object")
        and (.builds|has("latest"))
      then .builds.latest
      else empty
      end
    ')"

    [[ -n "${BUILD}" ]] || {
      log ERROR "Failed to resolve Purpur build. Response was:"
      log ERROR "$(echo "$json" | head -c 300)"
      die "Invalid Purpur build"
    }
  fi

  JAR_NAME="purpur-${VERSION}-${BUILD}.jar"

  download_file_atomic \
    "https://api.purpurmc.org/v2/purpur/${VERSION}/${BUILD}/download" \
    "${DATA_DIR}/server.jar" \
    "Purpur server.jar"

  log INFO "Purpur server.jar ready"
  write_server_install_marker "server.jar" "purpur" "${VERSION}" "${BUILD}"
}

install_mohist_server_artifact() {
  [[ -n "${VERSION:-}" ]] || die "VERSION is required for mohist"

  if [[ -f "${DATA_DIR}/server.jar" ]]; then
    assert_server_install_matches "server.jar" "mohist" "${VERSION}"
    log INFO "server.jar already exists, skipping"
    return
  fi

  log INFO "Installing Mohist server ${VERSION}"

  download_file_atomic \
    "https://mohistmc.com/api/v2/projects/mohist/${VERSION}/builds/latest/download" \
    "${DATA_DIR}/server.jar" \
    "Mohist server.jar"

  log INFO "Mohist server.jar ready"
  write_server_install_marker "server.jar" "mohist" "${VERSION}"
}

install_taiyitist_server_artifact() {
  [[ -n "${VERSION:-}" ]] || die "VERSION is required for taiyitist"

  if [[ -f "${DATA_DIR}/server.jar" ]]; then
    assert_server_install_matches "server.jar" "taiyitist" "${VERSION}"
    log INFO "server.jar already exists, skipping"
    return
  fi

  log INFO "Resolving Taiyitist ${VERSION} release asset"

  TAIYITIST_VERSION="${VERSION}-release"

  ASSET_URL=$(
    curl -fsSL "https://api.github.com/repos/TaiyitistMC/Taiyitist/releases/tags/${TAIYITIST_VERSION}" \
      | grep browser_download_url \
      | grep taiyitist-server \
      | cut -d '"' -f 4
  )

  [[ -n "${ASSET_URL}" ]] || die "Failed to resolve Taiyitist release asset"

  log INFO "Downloading ${ASSET_URL}"

  download_file_atomic "${ASSET_URL}" "${DATA_DIR}/server.jar" "Taiyitist server.jar"

  log INFO "Taiyitist server.jar ready"
  write_server_install_marker "server.jar" "taiyitist" "${VERSION}"
}

install_youer_server_artifact() {
  [[ -n "${VERSION:-}" ]] || die "VERSION is required for youer"

  if [[ -f "${DATA_DIR}/server.jar" ]]; then
    assert_server_install_matches "server.jar" "youer" "${VERSION}"
    log INFO "server.jar already exists, skipping"
    return
  fi

  log INFO "Installing Youer server ${VERSION}"

  download_file_atomic \
    "https://api.youer.org/v1/projects/youer/${VERSION}/builds/latest/download" \
    "${DATA_DIR}/server.jar" \
    "Youer server.jar"

  log INFO "Youer server.jar ready"
  write_server_install_marker "server.jar" "youer" "${VERSION}"
}

install_spigot_server_artifact() {
  [[ -n "${VERSION:-}" ]] || die "VERSION is required for spigot"

  if [[ -f "${DATA_DIR}/server.jar" ]]; then
    assert_server_install_matches "server.jar" "spigot" "${VERSION}"
    log INFO "server.jar already exists, using existing Spigot artifact"
    return
  fi

  die "TYPE=spigot requires an existing /data/server.jar; managed Spigot installer is not provided"
}
