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
  # Download
  # ------------------------------------------------------------
  configure_mc_alias "world"

  local TMP_ZIP EXTRACT_DIR
  TMP_ZIP="$(mktemp /tmp/world.XXXXXX.zip)" || return 1
  EXTRACT_DIR="$(mktemp -d /tmp/world-extract.XXXXXX)" || {
    rm -f "${TMP_ZIP}"
    return 1
  }

  mc cp "s3/${WORLD_S3_BUCKET}/${WORLD_S3_KEY}" "${TMP_ZIP}" || {
    rm -f "${TMP_ZIP}"
    rm -rf "${EXTRACT_DIR}"
    die "Failed to download world archive"
  }

  # ------------------------------------------------------------
  # Extract
  # ------------------------------------------------------------
  if ! unzip -q "${TMP_ZIP}" -d "${EXTRACT_DIR}"; then
    rm -f "${TMP_ZIP}"
    rm -rf "${EXTRACT_DIR}"
    log ERROR "Failed to extract world archive"
    return 1
  fi

  # ------------------------------------------------------------
  # Detect
  # ------------------------------------------------------------
  local SELECTED_SOURCE=""
  local CANDIDATES=()
  local TOP_LEVEL_DIRS=()
  local TOP_LEVEL_DIR

  while IFS= read -r -d '' TOP_LEVEL_DIR; do
    TOP_LEVEL_DIRS+=("${TOP_LEVEL_DIR}")
    if [[ -f "${TOP_LEVEL_DIR}/level.dat" ]]; then
      CANDIDATES+=("${TOP_LEVEL_DIR}")
    fi
  done < <(find "${EXTRACT_DIR}" -mindepth 1 -maxdepth 1 -type d -print0)

  if [[ -f "${EXTRACT_DIR}/level.dat" ]]; then
    CANDIDATES+=("${EXTRACT_DIR}")
  fi

  if [[ "${#CANDIDATES[@]}" -gt 1 ]]; then
    rm -f "${TMP_ZIP}"
    rm -rf "${EXTRACT_DIR}"
    log ERROR "Ambiguous world archive layout"
    return 1
  fi

  if [[ "${#CANDIDATES[@]}" -eq 0 ]]; then
    rm -f "${TMP_ZIP}"
    rm -rf "${EXTRACT_DIR}"
    log ERROR "Failed to detect world directory in archive"
    return 1
  fi

  SELECTED_SOURCE="${CANDIDATES[0]}"

  if [[ "${SELECTED_SOURCE}" != "${EXTRACT_DIR}" &&
    "${SELECTED_SOURCE}" != "${EXTRACT_DIR}/world" &&
    "${#TOP_LEVEL_DIRS[@]}" -ne 1 ]]; then
    rm -f "${TMP_ZIP}"
    rm -rf "${EXTRACT_DIR}"
    log ERROR "Ambiguous world archive layout"
    return 1
  fi

  # ------------------------------------------------------------
  # Install
  # ------------------------------------------------------------
  if ! mkdir -p "${DATA_DIR}"; then
    rm -f "${TMP_ZIP}"
    rm -rf "${EXTRACT_DIR}"
    return 1
  fi

  rm -rf "${WORLD_DIR}"
  if ! mv "${SELECTED_SOURCE}" "${WORLD_DIR}"; then
    rm -f "${TMP_ZIP}"
    rm -rf "${EXTRACT_DIR}"
    return 1
  fi

  rm -f "${TMP_ZIP}"
  rm -rf "${EXTRACT_DIR}"
  rm -f "${DATA_DIR}/reset-world.flag"

  log INFO "World installed successfully"
}
