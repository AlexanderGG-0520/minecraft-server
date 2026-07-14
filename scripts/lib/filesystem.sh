# shellcheck shell=bash

refuse_unsafe_filesystem_path() {
  local path="${1:-}"
  local action="${2:-operate on}"
  local resolved_path

  if [[ -z "${path}" || "${path}" == "/" ]]; then
    log ERROR "Refusing to ${action} unsafe path"
    return 1
  fi

  if command -v realpath >/dev/null 2>&1; then
    resolved_path="$(realpath -m -- "${path}")" || {
      log ERROR "Refusing to ${action} unsafe path"
      return 1
    }
    if [[ "${resolved_path}" == "/" ]]; then
      log ERROR "Refusing to ${action} unsafe path"
      return 1
    fi
  fi

  return 0
}

safe_rm_f() {
  local path="${1:-}"

  refuse_unsafe_filesystem_path "${path}" "remove" || return 1
  rm -f -- "${path}"
}

safe_rm_rf() {
  local path="${1:-}"

  refuse_unsafe_filesystem_path "${path}" "remove" || return 1
  rm -rf -- "${path}"
}

safe_mv() {
  local src="${1:-}"
  local dst="${2:-}"

  refuse_unsafe_filesystem_path "${src}" "move from" || return 1
  refuse_unsafe_filesystem_path "${dst}" "move to" || return 1
  mv -- "${src}" "${dst}"
}

safe_mv_f() {
  local src="${1:-}"
  local dst="${2:-}"

  refuse_unsafe_filesystem_path "${src}" "move from" || return 1
  refuse_unsafe_filesystem_path "${dst}" "move to" || return 1
  mv -f -- "${src}" "${dst}"
}

set_readable_file_permissions() {
  local path="${1:-}"

  refuse_unsafe_filesystem_path "${path}" "chmod" || return 1
  chmod 0644 -- "${path}" || die "Failed to set readable file permissions: ${path}"
}

content_input_is_explicit() {
  local variable="$1"
  local default_path="$2"
  local configured_variable="${variable}_CONFIGURED"

  [[ "${!configured_variable:-false}" == "true" ]] && return 0
  [[ -v "${variable}" && "${!variable}" != "${default_path}" ]]
}

path_is_within_directory() {
  local path="$1"
  local directory="$2"

  [[ "${path#"${directory}"/}" != "${path}" ]]
}

resolve_content_input_source() {
  local variable="$1"
  local default_path="$2"
  local destination="$3"
  local source="${!variable:-${default_path}}"
  local source_real destination_real

  # shellcheck disable=SC2034  # Read by the asset-specific activation function.
  CONTENT_INPUT_SOURCE="${source}"
  CONTENT_INPUT_SOURCE_ALREADY_ACTIVE=false

  if content_input_is_explicit "${variable}" "${default_path}"; then
    if [[ ! -e "${source}" ]]; then
      log ERROR "${variable} does not exist: ${source}"
      return 1
    fi
    if [[ ! -d "${source}" || ! -r "${source}" || ! -x "${source}" ]]; then
      log ERROR "${variable} must be a readable directory: ${source}"
      return 1
    fi
  elif [[ ! -d "${source}" ]]; then
    return 0
  fi

  if ! command -v realpath >/dev/null 2>&1; then
    log ERROR "realpath is required to resolve ${variable} content input paths"
    return 1
  fi

  source_real="$(realpath -e -- "${source}")" || {
    log ERROR "${variable} must be a readable directory: ${source}"
    return 1
  }
  destination_real="$(realpath -m -- "${destination}")" || {
    log ERROR "Failed to resolve active destination for ${variable}: ${destination}"
    return 1
  }

  if [[ "${source_real}" == "${destination_real}" ]]; then
    # shellcheck disable=SC2034  # Read by the asset-specific activation function.
    CONTENT_INPUT_SOURCE="${source_real}"
    # shellcheck disable=SC2034  # Read by the asset-specific activation function.
    CONTENT_INPUT_SOURCE_ALREADY_ACTIVE=true
    log INFO "${variable} is already the active destination; skipping activation"
    return 0
  fi

  if path_is_within_directory "${destination_real}" "${source_real}" \
    || path_is_within_directory "${source_real}" "${destination_real}"; then
    log ERROR "${variable} overlaps its active destination; source and destination must not overlap: ${source} -> ${destination}"
    return 1
  fi

  # shellcheck disable=SC2034  # Read by the asset-specific activation function.
  CONTENT_INPUT_SOURCE="${source_real}"
}
