# shellcheck shell=bash

install_world() {
  local WORLD_DIR="${DATA_DIR}/world"

  # ------------------------------------------------------------
  # Guard
  # ------------------------------------------------------------
  if [[ -d "${WORLD_DIR}" && ! -f "${DATA_DIR}/reset-world.flag" ]]; then
    log INFO "World already exists, skipping world install"
    return 0
  fi

  if [[ -z "${WORLD_S3_BUCKET:-}" || -z "${WORLD_S3_KEY:-}" ]]; then
    log INFO "WORLD_S3_BUCKET or WORLD_S3_KEY not set, skipping world install"
    return 0
  fi

  log INFO "Installing world from S3"

  # ------------------------------------------------------------
  # Prepare
  # ------------------------------------------------------------
  rm -rf "${WORLD_DIR}"
  mkdir -p "${WORLD_DIR}"

  # ------------------------------------------------------------
  # Download
  # ------------------------------------------------------------
  configure_mc_alias "world"

  local TMP_ZIP
  TMP_ZIP="$(mktemp /tmp/world.XXXXXX.zip)" || return 1

  mc cp "s3/${WORLD_S3_BUCKET}/${WORLD_S3_KEY}" "${TMP_ZIP}" || {
    rm -f "${TMP_ZIP}"
    die "Failed to download world archive"
  }

  # ------------------------------------------------------------
  # Extract
  # ------------------------------------------------------------
  if ! unzip -q "${TMP_ZIP}" -d "${DATA_DIR}"; then
    rm -f "${TMP_ZIP}"
    return 1
  fi

  # Safety check if world/ is not directly inside zip
  if [[ ! -d "${WORLD_DIR}" ]]; then
    local EXTRACTED
    EXTRACTED="$(find "${DATA_DIR}" -maxdepth 1 -type d -name "*world*" | head -n1 || true)"
    [[ -n "${EXTRACTED}" ]] && mv "${EXTRACTED}" "${WORLD_DIR}"
  fi

  rm -f "${TMP_ZIP}"
  rm -f "${DATA_DIR}/reset-world.flag"

  log INFO "World installed successfully"
}
