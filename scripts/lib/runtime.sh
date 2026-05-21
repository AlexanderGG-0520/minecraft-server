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

read_server_install_marker_field() {
  local marker="$1"
  local field="$2"
  local value

  if ! jq -e 'type == "object"' "$marker" >/dev/null 2>&1; then
    die "Corrupt server install marker"
  fi

  if ! jq -e --arg field "$field" 'has($field) and .[$field] != null' "$marker" >/dev/null 2>&1; then
    die "Incomplete server install marker"
  fi

  if ! value="$(jq -r --arg field "$field" '.[$field]' "$marker" 2>/dev/null)"; then
    die "Corrupt server install marker"
  fi

  printf '%s' "$value"
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
  installed_artifact="$(read_server_install_marker_field "$marker" artifact)"
  installed_type="$(read_server_install_marker_field "$marker" type)"
  installed_version="$(read_server_install_marker_field "$marker" version)"
  read_server_install_marker_field "$marker" build >/dev/null

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
  local marker marker_dir tmp
  marker="$(server_install_marker)"
  marker_dir="$(dirname "$marker")"
  tmp="$(mktemp "${marker_dir}/.server-install.json.tmp.XXXXXX")" || return 1

  if ! jq -n \
    --arg artifact "$artifact" \
    --arg type "$installed_type" \
    --arg version "$installed_version" \
    --arg build "$build" \
    '{artifact:$artifact,type:$type,version:$version,build:$build}' > "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi

  if ! mv -f "$tmp" "$marker"; then
    rm -f -- "$tmp"
    return 1
  fi

  rm -f -- "$tmp"
}

resolve_type_auto() {
  [[ "${TYPE:-}" == "auto" || "${TYPE:-}" == "AUTO" ]] || return 0

  local marker installed_type installed_artifact
  marker="$(server_install_marker)"

  if [[ -f "${marker}" ]]; then
    installed_artifact="$(read_server_install_marker_field "${marker}" artifact)"
    installed_type="$(read_server_install_marker_field "${marker}" type)"
    read_server_install_marker_field "${marker}" version >/dev/null
    read_server_install_marker_field "${marker}" build >/dev/null

    case "${installed_type}" in
      fabric|forge|mohist|neoforge|paper|purpur|quilt|spigot|taiyitist|vanilla|velocity|youer)
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
