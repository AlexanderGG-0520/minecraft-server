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
