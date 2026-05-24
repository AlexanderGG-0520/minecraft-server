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
