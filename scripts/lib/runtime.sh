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

is_managed_server_artifact() {
  local artifact="$1"
  case "$artifact" in
    fabric-server-launch.jar|run.sh|server.jar|velocity.jar)
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

is_force_reinstall_enabled() {
  [[ "${FORCE_REINSTALL:-false}" == "true" ]]
}

validate_server_install_marker() {
  local marker="$1"
  local field

  if ! jq '.' "$marker" >/dev/null 2>&1; then
    die "Invalid/corrupt server install marker JSON: ${marker}"
  fi

  if ! jq -e 'type == "object"' "$marker" >/dev/null 2>&1; then
    die "Invalid server install marker: ${marker} must be a JSON object"
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
  installed_type="$(jq -r '.type' "$marker")" || die "Invalid/corrupt server install marker JSON: ${marker}"
  if ! is_supported_runtime_type "$installed_type"; then
    die "Invalid server install marker: ${marker} unsupported type ${installed_type}"
  fi

  local installed_artifact
  installed_artifact="$(jq -r '.artifact' "$marker")" || die "Invalid/corrupt server install marker JSON: ${marker}"
  if ! is_managed_server_artifact "$installed_artifact"; then
    die "Invalid server install marker: ${marker} unsupported artifact ${installed_artifact}"
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
    die "Invalid/corrupt server install marker JSON: ${marker}"
  fi

  printf '%s' "$value"
}

server_install_mismatch_summary() {
  local installed_artifact="$1"
  local requested_artifact="$2"
  local installed_type="$3"
  local requested_type="$4"
  local installed_version="$5"
  local requested_version="$6"
  local installed_build="$7"
  local requested_build="$8"
  local mismatches=()
  local mismatch summary=""

  if [[ "$installed_artifact" != "$requested_artifact" ]]; then
    mismatches+=("artifact current=${installed_artifact:-<empty>} requested=${requested_artifact:-<empty>}")
  fi
  if [[ "$installed_type" != "$requested_type" ]]; then
    mismatches+=("type current=${installed_type:-<empty>} requested=${requested_type:-<empty>}")
  fi
  if [[ "$installed_version" != "$requested_version" ]]; then
    mismatches+=("version current=${installed_version:-<empty>} requested=${requested_version:-<empty>}")
  fi
  if [[ "$installed_build" != "$requested_build" ]]; then
    mismatches+=("build current=${installed_build:-<empty>} requested=${requested_build:-<empty>}")
  fi

  for mismatch in "${mismatches[@]}"; do
    if [[ -n "$summary" ]]; then
      summary="${summary}; ${mismatch}"
    else
      summary="$mismatch"
    fi
  done

  printf '%s' "$summary"
}

remove_server_install_state() {
  local artifact="$1"
  local requested_type="$2"
  local marker="$3"
  local extra_marker

  safe_rm_f "${DATA_DIR}/${artifact}"
  safe_rm_f "$marker"

  case "$requested_type" in
    forge)
      for extra_marker in "${DATA_DIR}"/.installed-forge-*; do
        [[ -e "$extra_marker" ]] || continue
        safe_rm_f "$extra_marker"
      done
      ;;
    neoforge)
      for extra_marker in "${DATA_DIR}"/.installed-neoforge-*; do
        [[ -e "$extra_marker" ]] || continue
        safe_rm_f "$extra_marker"
      done
      ;;
  esac
}

assert_server_install_matches() {
  local artifact="$1"
  local requested_type="$2"
  local requested_version="$3"
  local requested_build="${4:-}"
  local marker
  marker="$(server_install_marker)"

  if [[ ! -f "$marker" ]]; then
    log WARN "${artifact} exists without install marker; leaving it in place"
    return 0
  fi

  local installed_type installed_version installed_artifact installed_build mismatches
  installed_artifact="$(read_server_install_marker_field "$marker" artifact)"
  installed_type="$(read_server_install_marker_field "$marker" type)"
  installed_version="$(read_server_install_marker_field "$marker" version)"
  installed_build="$(read_server_install_marker_field "$marker" build)"

  if [[ "$installed_type" != "$requested_type" \
     || "$installed_version" != "$requested_version" \
     || "$installed_artifact" != "$artifact" \
     || "$installed_build" != "$requested_build" ]]; then
    mismatches="$(
      server_install_mismatch_summary \
        "$installed_artifact" "$artifact" \
        "$installed_type" "$requested_type" \
        "$installed_version" "$requested_version" \
        "$installed_build" "$requested_build"
    )"

    if is_force_reinstall_enabled; then
      log WARN "Server install marker mismatch at ${marker}: ${mismatches}; FORCE_REINSTALL=true, removing managed server artifact and marker before reinstall"
      remove_server_install_state "$installed_artifact" "$installed_type" "$marker"
      if [[ "$installed_artifact" != "$artifact" ]]; then
        safe_rm_f "${DATA_DIR}/${artifact}"
      fi
      return 1
    fi

    die "Server install marker mismatch at ${marker}: ${mismatches}. Refusing to replace existing server artifact automatically. Set FORCE_REINSTALL=true only if you intentionally want to reinstall the server artifact"
  fi
}

cleanup_server_install_marker_tmp() {
  local tmp="${1:-}"

  [[ -z "$tmp" ]] || safe_rm_f "$tmp"
}

write_server_install_marker() {
  local artifact="$1"
  local installed_type="$2"
  local installed_version="$3"
  local build="${4:-}"
  local marker marker_dir tmp
  marker="$(server_install_marker)"
  marker_dir="$(dirname "$marker")"
  tmp="$(mktemp "${marker_dir}/.server-install.json.tmp.XXXXXX")" \
    || die "Failed to create temporary server install marker: ${marker}"

  if ! jq -n \
    --arg artifact "$artifact" \
    --arg type "$installed_type" \
    --arg version "$installed_version" \
    --arg build "$build" \
    '{artifact:$artifact,type:$type,version:$version,build:$build}' > "$tmp"; then
    cleanup_server_install_marker_tmp "$tmp"
    return 1
  fi

  if ! safe_mv_f "$tmp" "$marker"; then
    cleanup_server_install_marker_tmp "$tmp"
    return 1
  fi
  set_readable_file_permissions "$marker"

  cleanup_server_install_marker_tmp "$tmp"
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
