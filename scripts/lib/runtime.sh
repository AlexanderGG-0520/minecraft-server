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

validate_server_install_marker() {
  local marker="$1"
  local field

  if ! jq -e 'type == "object"' "$marker" >/dev/null 2>&1; then
    die "Invalid server install marker JSON: ${marker}"
  fi

  for field in artifact type version build; do
    if ! jq -e --arg field "$field" 'has($field) and .[$field] != null' "$marker" >/dev/null 2>&1; then
      die "Incomplete server install marker: ${marker} missing ${field}"
    fi

    if ! jq -e --arg field "$field" '.[$field] | type == "string"' "$marker" >/dev/null 2>&1; then
      die "Invalid server install marker: ${marker} field ${field} must be a string"
    fi
  done

  for field in artifact type version; do
    if ! jq -e --arg field "$field" '.[$field] | length > 0' "$marker" >/dev/null 2>&1; then
      die "Invalid server install marker: ${marker} field ${field} must not be empty"
    fi
  done

  local installed_type
  installed_type="$(jq -r '.type' "$marker")" || die "Invalid server install marker JSON: ${marker}"
  if ! is_supported_runtime_type "$installed_type"; then
    die "Invalid server install marker: ${marker} unsupported type ${installed_type}"
  fi
}

read_server_install_marker_field() {
  local marker="$1"
  local field="$2"
  local value

  validate_server_install_marker "$marker"
  if ! jq -e --arg field "$field" 'has($field) and .[$field] != null' "$marker" >/dev/null 2>&1; then
    die "Incomplete server install marker: ${marker} missing ${field}"
  fi

  if ! value="$(jq -r --arg field "$field" '.[$field]' "$marker" 2>/dev/null)"; then
    die "Invalid server install marker JSON: ${marker}"
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
    safe_rm_f "$tmp"
    return 1
  fi

  if ! safe_mv_f "$tmp" "$marker"; then
    safe_rm_f "$tmp"
    return 1
  fi
  set_readable_file_permissions "$marker"

  safe_rm_f "$tmp"
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

    if [[ -e "${DATA_DIR}/${installed_artifact}" ]]; then
      TYPE="${installed_type}"
      log INFO "TYPE auto-resolved to '${TYPE}' from install marker"
      return 0
    fi
    log WARN "Install marker exists but artifact is missing, falling back to artifact detection: ${installed_artifact}"
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
