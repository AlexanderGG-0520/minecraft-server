# shellcheck shell=bash

validate_world_reset_flag_path() {
  local data_dir="${1:-}"
  local flag_path="${2:-}"

  if [[ -z "${data_dir}" ]]; then
    log ERROR "DATA_DIR is required for world reset"
    return 1
  fi

  if [[ -z "${flag_path}" ]]; then
    log ERROR "Refusing unsafe reset flag path"
    return 1
  fi

  if [[ "${data_dir}" != /* || "${data_dir}" == "/" ]]; then
    log ERROR "Refusing unsafe reset flag path"
    return 1
  fi

  if [[ "${flag_path}" != "${data_dir}/reset-world.flag" ]]; then
    log ERROR "Refusing unsafe reset flag path"
    return 1
  fi

  case "${flag_path}" in
    /|/reset-world.flag|/tmp/reset-world.flag|/data)
      log ERROR "Refusing unsafe reset flag path"
      return 1
      ;;
  esac

  if [[ "${flag_path}" == "${data_dir}" ]]; then
    log ERROR "Refusing unsafe reset flag path"
    return 1
  fi

  if ! command -v realpath >/dev/null 2>&1; then
    log ERROR "Refusing unsafe reset flag path"
    return 1
  fi

  local resolved_data_dir resolved_flag_path expected_flag_path
  if ! resolved_data_dir="$(realpath -m -- "${data_dir}")"; then
    log ERROR "Refusing unsafe reset flag path"
    return 1
  fi

  if ! resolved_flag_path="$(realpath -m -- "${flag_path}")"; then
    log ERROR "Refusing unsafe reset flag path"
    return 1
  fi

  if ! expected_flag_path="$(realpath -m -- "${resolved_data_dir}/reset-world.flag")"; then
    log ERROR "Refusing unsafe reset flag path"
    return 1
  fi

  if [[ "${resolved_data_dir}" == "/" ||
    "${resolved_flag_path}" == "/" ||
    "${resolved_flag_path}" == "/reset-world.flag" ||
    "${resolved_flag_path}" == "/tmp/reset-world.flag" ||
    "${resolved_flag_path}" == "/data" ||
    "${resolved_flag_path}" == "${resolved_data_dir}" ||
    "${resolved_flag_path}" != "${expected_flag_path}" ||
    "${resolved_flag_path##*/}" != "reset-world.flag" ]]; then
    log ERROR "Refusing unsafe reset flag path"
    return 1
  fi

  case "${resolved_flag_path}" in
    "${resolved_data_dir}"/*) ;;
    *)
      log ERROR "Refusing unsafe reset flag path"
      return 1
      ;;
  esac

  return 0
}

remove_reset_world_flag() {
  local data_dir="${1:-}"
  local flag_path="${2:-}"

  validate_world_reset_flag_path "${data_dir}" "${flag_path}" || return 1
  safe_rm_f "${flag_path}"
}

validate_world_reset_paths() {
  local data_dir="${1:-}"
  local world_dir="${2:-}"
  local flag_file="${3:-}"
  local backup_dir="${4:-}"
  local backup_archive="${5:-}"
  local mods_dir="${6:-}"
  local remove_mods="${7:-false}"
  local backup_enabled="${8:-true}"

  if [[ -z "${data_dir}" ]]; then
    log ERROR "DATA_DIR is required for world reset"
    return 1
  fi

  if [[ -z "${world_dir}" ||
    -z "${flag_file}" ||
    -z "${backup_dir}" ||
    "${data_dir}" != /* ||
    "${data_dir}" == "/" ]]; then
    log ERROR "Refusing unsafe world reset path"
    return 1
  fi

  if [[ "${world_dir}" != "${data_dir}/world" ||
    "${backup_dir}" != "${data_dir}/backups" ]]; then
    log ERROR "Refusing unsafe world reset path"
    return 1
  fi

  if [[ "${flag_file}" != "${data_dir}/reset-world.flag" ]]; then
    log ERROR "Refusing unsafe reset flag path"
    return 1
  fi

  case "${world_dir}" in
    /|/world|/tmp|/data)
      log ERROR "Refusing unsafe world reset path"
      return 1
      ;;
  esac

  if [[ "${world_dir}" == "${data_dir}" ]]; then
    log ERROR "Refusing unsafe world reset path"
    return 1
  fi

  if ! command -v realpath >/dev/null 2>&1; then
    log ERROR "Refusing unsafe world reset path"
    return 1
  fi

  local resolved_data_dir resolved_world_dir expected_world_dir
  local resolved_flag_file expected_flag_file
  local resolved_backup_dir expected_backup_dir resolved_backup_archive
  if ! resolved_data_dir="$(realpath -m -- "${data_dir}")"; then
    log ERROR "Refusing unsafe world reset path"
    return 1
  fi

  if ! resolved_world_dir="$(realpath -m -- "${world_dir}")"; then
    log ERROR "Refusing unsafe world reset path"
    return 1
  fi

  if ! expected_world_dir="$(realpath -m -- "${resolved_data_dir}/world")"; then
    log ERROR "Refusing unsafe world reset path"
    return 1
  fi

  if ! resolved_flag_file="$(realpath -m -- "${flag_file}")"; then
    log ERROR "Refusing unsafe reset flag path"
    return 1
  fi

  if ! expected_flag_file="$(realpath -m -- "${resolved_data_dir}/reset-world.flag")"; then
    log ERROR "Refusing unsafe reset flag path"
    return 1
  fi

  if ! resolved_backup_dir="$(realpath -m -- "${backup_dir}")"; then
    log ERROR "Refusing unsafe world reset path"
    return 1
  fi

  if ! expected_backup_dir="$(realpath -m -- "${resolved_data_dir}/backups")"; then
    log ERROR "Refusing unsafe world reset path"
    return 1
  fi

  if [[ "${resolved_data_dir}" == "/" ||
    "${resolved_world_dir}" == "/" ||
    "${resolved_world_dir}" == "/world" ||
    "${resolved_world_dir}" == "/tmp" ||
    "${resolved_world_dir}" == "/data" ||
    "${resolved_world_dir}" == "${resolved_data_dir}" ||
    "${resolved_world_dir}" != "${expected_world_dir}" ||
    "${resolved_world_dir##*/}" != "world" ||
    "${resolved_flag_file}" != "${expected_flag_file}" ||
    "${resolved_flag_file##*/}" != "reset-world.flag" ||
    "${resolved_backup_dir}" != "${expected_backup_dir}" ||
    "${resolved_backup_dir}" == "${resolved_data_dir}" ||
    "${resolved_backup_dir##*/}" != "backups" ]]; then
    log ERROR "Refusing unsafe world reset path"
    return 1
  fi

  case "${resolved_world_dir}" in
    "${resolved_data_dir}"/*) ;;
    *)
      log ERROR "Refusing unsafe world reset path"
      return 1
      ;;
  esac

  case "${resolved_flag_file}" in
    "${resolved_data_dir}"/*) ;;
    *)
      log ERROR "Refusing unsafe reset flag path"
      return 1
      ;;
  esac

  case "${resolved_backup_dir}" in
    "${resolved_data_dir}"/*) ;;
    *)
      log ERROR "Refusing unsafe world reset path"
      return 1
      ;;
  esac

  if [[ "${backup_enabled}" == "true" ]]; then
    if [[ -z "${backup_archive}" ]]; then
      log ERROR "Refusing unsafe world reset path"
      return 1
    fi

    if ! resolved_backup_archive="$(realpath -m -- "${backup_archive}")"; then
      log ERROR "Refusing unsafe world reset path"
      return 1
    fi

    case "${resolved_backup_archive}" in
      "${resolved_backup_dir}"/*) ;;
      *)
        log ERROR "Refusing unsafe world reset path"
        return 1
        ;;
    esac
  fi

  if [[ "${remove_mods}" == "true" ]]; then
    if [[ -z "${mods_dir}" || "${mods_dir}" != "${data_dir}/mods" ]]; then
      log ERROR "Refusing unsafe world reset path"
      return 1
    fi

    local resolved_mods_dir expected_mods_dir
    if ! resolved_mods_dir="$(realpath -m -- "${mods_dir}")"; then
      log ERROR "Refusing unsafe world reset path"
      return 1
    fi

    if ! expected_mods_dir="$(realpath -m -- "${resolved_data_dir}/mods")"; then
      log ERROR "Refusing unsafe world reset path"
      return 1
    fi

    if [[ "${resolved_mods_dir}" == "/" ||
      "${resolved_mods_dir}" == "/mods" ||
      "${resolved_mods_dir}" == "/tmp" ||
      "${resolved_mods_dir}" == "/data" ||
      "${resolved_mods_dir}" == "${resolved_data_dir}" ||
      "${resolved_mods_dir}" == "${resolved_world_dir}" ||
      "${resolved_mods_dir}" != "${expected_mods_dir}" ||
      "${resolved_mods_dir##*/}" != "mods" ]]; then
      log ERROR "Refusing unsafe world reset path"
      return 1
    fi

    case "${resolved_mods_dir}" in
      "${resolved_data_dir}"/*) ;;
      *)
        log ERROR "Refusing unsafe world reset path"
        return 1
        ;;
    esac
  fi

  return 0
}

reset_world() {
  log INFO "Requested world reset"

  local FLAG_FILE="${DATA_DIR:-}/reset-world.flag"  # flag file path

  # ---- Safety check 1: explicit confirmation ----
  if [[ ! -f "${FLAG_FILE}" ]]; then
    log INFO "reset-world.flag file is missing, cannot proceed with world reset"
    return  # return instead of die to avoid stopping the script
  fi

  local WORLD_DIR="${DATA_DIR:-}/world"
  local MODS_DIR="${DATA_DIR:-}/mods"

  # ---- Safety check 2: directory sanity ----
  if [[ ! -d "${WORLD_DIR}" ]]; then
    log INFO "World directory does not exist, nothing to reset"
    return
  fi

  if [[ "${WORLD_DIR}" == "/" || "${WORLD_DIR}" == "${DATA_DIR}" ]]; then
    log ERROR "Unsafe WORLD_DIR detected: ${WORLD_DIR}"
    return  # stop instead of die
  fi

  local BACKUP_DIR="${DATA_DIR:-}/backups"
  local BACKUP_ARCHIVE=""
  if [[ "${RESET_WORLD_BACKUP:-true}" == "true" ]]; then
    local TS
    TS="$(date -u +'%Y%m%d-%H%M%S')"
    BACKUP_ARCHIVE="${BACKUP_DIR}/world-${TS}.tar.gz"
  fi

  validate_world_reset_paths \
    "${DATA_DIR:-}" \
    "${WORLD_DIR}" \
    "${FLAG_FILE}" \
    "${BACKUP_DIR}" \
    "${BACKUP_ARCHIVE}" \
    "${MODS_DIR}" \
    "${RESET_WORLD_REMOVE_MODS:-false}" \
    "${RESET_WORLD_BACKUP:-true}" || return 1

  log INFO "Resetting world at ${WORLD_DIR}"

  # ---- Step 1: mark NotReady ----
  safe_rm_f "${DATA_DIR}/.ready"

  # ---- Step 2: optional backup ----
  if [[ "${RESET_WORLD_BACKUP:-true}" == "true" ]]; then
    mkdir -p "${BACKUP_DIR}"

    log INFO "Creating world backup"
    tar -czf "${BACKUP_ARCHIVE}" -C "${DATA_DIR}" world \
      || die "World backup failed; refusing to delete world"
  fi

  # ---- Step 3: delete world directory completely ----
  log INFO "Deleting world directory"
  safe_rm_rf "${WORLD_DIR}" || return 1
  mkdir -p "${WORLD_DIR}"
  if [[ "${RESET_WORLD_REMOVE_MODS:-false}" == "true" ]]; then
    log WARN "RESET_WORLD_REMOVE_MODS=true, deleting mods directory"
    safe_rm_rf "${MODS_DIR}" || return 1
    mkdir -p "${MODS_DIR}"
  fi
  log INFO "World directory reset complete"

  # ---- Step 4: delete the FLAG file to prevent repeated resets ----
  remove_reset_world_flag "${DATA_DIR:-}" "${FLAG_FILE}" || return 1

  log INFO "World reset completed successfully"
}

handle_reset_world_flag() {
  local MAX_AGE=1800  # 30 minutes
  local FLAG="${DATA_DIR:-}/reset-world.flag"

  if [[ -f "$FLAG" ]]; then
    local NOW
    local MTIME
    NOW=$(date +%s)
    MTIME=$(stat -c %Y "$FLAG")

    if (( NOW - MTIME > MAX_AGE )); then
      log ERROR "reset-world.flag expired (older than ${MAX_AGE}s), resetting aborted"
      remove_reset_world_flag "${DATA_DIR:-}" "${FLAG}" || return 1
      return
    fi

    log WARN "reset-world.flag valid, proceeding to reset world"
    reset_world || return 1
    if [[ -f "${FLAG}" ]]; then
      remove_reset_world_flag "${DATA_DIR:-}" "${FLAG}" || return 1
    fi
    log INFO "reset-world.flag consumed"
  else
    log INFO "No reset-world.flag detected, skipping world reset"
  fi
}
