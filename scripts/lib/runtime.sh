# shellcheck shell=bash

is_auto_type() {
  local type="$1"
  [[ "$type" == "auto" || "$type" == "AUTO" ]]
}

is_supported_runtime_type() {
  local type="$1"
  case "$type" in
    fabric|forge|mohist|neoforge|paper|purpur|quilt|spigot|taiyitist|vanilla|velocity|youer)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

uses_server_properties() {
  local type="$1"
  case "$type" in
    vanilla|paper|purpur|spigot|fabric|forge|neoforge)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_type_auto() {
  [[ "${TYPE:-}" == "auto" || "${TYPE:-}" == "AUTO" ]] || return 0

  local marker installed_type installed_artifact
  marker="$(server_install_marker)"

  if [[ -f "${marker}" ]]; then
    installed_type="$(jq -r '.type // empty' "${marker}" 2>/dev/null || true)"
    installed_artifact="$(jq -r '.artifact // empty' "${marker}" 2>/dev/null || true)"

    case "${installed_type}" in
      fabric|forge|mohist|neoforge|paper|purpur|quilt|taiyitist|vanilla|velocity|youer)
        if [[ -n "${installed_artifact}" && -e "${DATA_DIR}/${installed_artifact}" ]]; then
          TYPE="${installed_type}"
          log INFO "TYPE auto-resolved to '${TYPE}' from install marker"
          return 0
        fi
        log WARN "Install marker exists but artifact is missing, falling back to artifact detection: ${installed_artifact:-unknown}"
        ;;
      "")
        log WARN "Install marker exists but type is empty, falling back to artifact detection"
        ;;
      *)
        log WARN "Install marker has unsupported type '${installed_type}', falling back to artifact detection"
        ;;
    esac
  fi

  if [[ -f "${DATA_DIR}/velocity.jar" ]]; then
    TYPE="velocity"
  elif [[ -f "${DATA_DIR}/fabric-server-launch.jar" ]]; then
    TYPE="fabric"
  elif [[ -f "${DATA_DIR}/run.sh" ]]; then
    if compgen -G "${DATA_DIR}/.installed-neoforge-*" > /dev/null; then
      TYPE="neoforge"
    else
      TYPE="forge"
    fi
  elif [[ -f "${DATA_DIR}/server.jar" ]]; then
    TYPE="vanilla"
  else
    TYPE="vanilla"
  fi

  log INFO "TYPE auto-resolved to '${TYPE}'"
}
