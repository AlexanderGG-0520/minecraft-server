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

server_install_marker() {
  printf '%s/.server-install.json' "${DATA_DIR}"
}

assert_server_install_matches() {
  local artifact="$1"
  local requested_type="$2"
  local requested_version="$3"
  local marker
  marker="$(server_install_marker)"

  if [[ ! -f "$marker" ]]; then
    log WARN "${artifact} exists without install marker; leaving it in place"
    return 0
  fi

  local installed_type installed_version installed_artifact
  installed_type="$(jq -r '.type // empty' "$marker")"
  installed_version="$(jq -r '.version // empty' "$marker")"
  installed_artifact="$(jq -r '.artifact // empty' "$marker")"

  if [[ "$installed_type" != "$requested_type" \
     || "$installed_version" != "$requested_version" \
     || "$installed_artifact" != "$artifact" ]]; then
    die "${artifact} was installed as TYPE=${installed_type:-unknown} VERSION=${installed_version:-unknown}; requested TYPE=${requested_type} VERSION=${requested_version}. Refusing to replace existing server artifact automatically"
  fi
}

write_server_install_marker() {
  local artifact="$1"
  local installed_type="$2"
  local installed_version="$3"
  local build="${4:-}"
  local marker tmp
  marker="$(server_install_marker)"
  tmp="${marker}.tmp.$$"

  jq -n \
    --arg artifact "$artifact" \
    --arg type "$installed_type" \
    --arg version "$installed_version" \
    --arg build "$build" \
    '{artifact:$artifact,type:$type,version:$version,build:$build}' > "$tmp"
  mv -f "$tmp" "$marker"
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
