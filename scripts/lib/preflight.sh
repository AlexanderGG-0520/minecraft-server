# shellcheck shell=bash

preflight() {
  log INFO "Preflight checks..."

  [[ -d "${DATA_DIR}" ]] || die "${DATA_DIR} does not exist"
  touch "${DATA_DIR}/.write_test" 2>/dev/null || die "${DATA_DIR} is not writable"
  safe_rm_f "${DATA_DIR}/.write_test"

  [[ -n "${EULA:-}" ]] || die "EULA is not set"

  if ! is_auto_type "${TYPE:-vanilla}" && ! is_supported_runtime_type "${TYPE:-vanilla}"; then
    die "Invalid TYPE: ${TYPE}"
  fi

  if [[ "${TYPE:-vanilla}" != "vanilla" && "${TYPE:-vanilla}" != "auto" && -z "${VERSION:-}" ]]; then
    die "VERSION must be set when TYPE is not vanilla"
  fi

  if [[ "${ENABLE_RCON}" == "true" ]]; then
    [[ -n "${RCON_PASSWORD:-}" ]] || die "ENABLE_RCON=true but RCON_PASSWORD is empty"
    [[ "${RCON_PASSWORD}" != "changeme" ]] || die "RCON_PASSWORD=changeme is not allowed"
  fi

  safe_rm_f "${DATA_DIR}/.ready"
  log INFO "Preflight OK"
}
