# shellcheck shell=bash

install_dirs() {
  log INFO "Preparing directory structure"

  mkdir -p \
    "${DATA_DIR}/logs" \
    "${DATA_DIR}/config" \
    "${DATA_DIR}/world"

  if [[ "${TYPE}" == "paper" || "${TYPE}" == "purpur" || "${TYPE}" == "spigot" ]]; then
    mkdir -p "${DATA_DIR}/plugins"
  fi

  if [[ "${TYPE}" == "fabric" || "${TYPE}" == "forge" || "${TYPE}" == "neoforge" ]]; then
    mkdir -p "${INPUT_MODS_DIR}"
  fi

  # Permissions check
  touch "${DATA_DIR}/logs/.perm_test" 2>/dev/null || die "${DATA_DIR}/logs is not writable"
  safe_rm_f "${DATA_DIR}/logs/.perm_test"

  log INFO "Directory structure ready"
}

install_eula() {
  log INFO "Handling EULA"

  case "${EULA}" in
    true)
      echo "eula=true" > "${DATA_DIR}/eula.txt"
      log INFO "EULA accepted"
      ;;
    false)
      die "EULA=false. You must accept the EULA to run the server"
      ;;
    *)
      die "Invalid EULA value: ${EULA} (expected true or false)"
      ;;
  esac
}

setup_server_icon() {
  if [[ -z "${SERVER_ICON_URL:-}" ]]; then
    log INFO "SERVER_ICON_URL not set, skipping server icon setup"
    return 0
  fi

  local icon_path="${DATA_DIR}/server-icon.png"

  if [[ -f "${icon_path}" ]]; then
    log INFO "server-icon.png already exists, skipping overwrite"
    return 0
  fi

  log INFO "Setting server icon from ${SERVER_ICON_URL}"

  if ! curl -fsSL "${SERVER_ICON_URL}" -o "${icon_path}"; then
    log ERROR "Failed to download server icon"
    safe_rm_f "${icon_path}"
    return 1
  fi

  log INFO "Server icon installed: ${icon_path}"
}
