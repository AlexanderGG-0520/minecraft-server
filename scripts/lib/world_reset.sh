# shellcheck shell=bash

reset_world() {
  log INFO "Requested world reset"

  FLAG_FILE="${DATA_DIR}/reset-world.flag"  # flag file path

  # ---- Safety check 1: explicit confirmation ----
  if [[ ! -f "${FLAG_FILE}" ]]; then
    log INFO "reset-world.flag file is missing, cannot proceed with world reset"
    return  # return instead of die to avoid stopping the script
  fi

  WORLD_DIR="${DATA_DIR}/world"
  MODS_DIR="${DATA_DIR}/mods"

  # ---- Safety check 2: directory sanity ----
  if [[ ! -d "${WORLD_DIR}" ]]; then
    log INFO "World directory does not exist, nothing to reset"
    return
  fi

  if [[ "${WORLD_DIR}" == "/" || "${WORLD_DIR}" == "${DATA_DIR}" ]]; then
    log ERROR "Unsafe WORLD_DIR detected: ${WORLD_DIR}"
    return  # stop instead of die
  fi

  log INFO "Resetting world at ${WORLD_DIR}"

  # ---- Step 1: mark NotReady ----
  rm -f "${DATA_DIR}/.ready"

  # ---- Step 2: optional backup ----
  if [[ "${RESET_WORLD_BACKUP:-true}" == "true" ]]; then
    TS="$(date -u +'%Y%m%d-%H%M%S')"
    BACKUP_DIR="${DATA_DIR}/backups"
    mkdir -p "${BACKUP_DIR}"

    log INFO "Creating world backup"
    tar -czf "${BACKUP_DIR}/world-${TS}.tar.gz" -C "${DATA_DIR}" world \
      || die "World backup failed; refusing to delete world"
  fi

  # ---- Step 3: delete world directory completely ----
  log INFO "Deleting world directory"
  rm -rf "${WORLD_DIR}"
  mkdir -p "${WORLD_DIR}"
  if [[ "${RESET_WORLD_REMOVE_MODS:-false}" == "true" ]]; then
    log WARN "RESET_WORLD_REMOVE_MODS=true, deleting mods directory"
    rm -rf "${MODS_DIR}"
    mkdir -p "${MODS_DIR}"
  fi
  log INFO "World directory reset complete"

  # ---- Step 4: delete the FLAG file to prevent repeated resets ----
  rm -f "${FLAG_FILE}"

  log INFO "World reset completed successfully"
}

handle_reset_world_flag() {
  MAX_AGE=1800  # 30 minutes
  FLAG="${DATA_DIR}/reset-world.flag"

  if [[ -f "$FLAG" ]]; then
    NOW=$(date +%s)
    MTIME=$(stat -c %Y "$FLAG")

    if (( NOW - MTIME > MAX_AGE )); then
      log ERROR "reset-world.flag expired (older than ${MAX_AGE}s), resetting aborted"
      rm -f "$FLAG"
      return
    fi

    log WARN "reset-world.flag valid, proceeding to reset world"
    reset_world
    rm -f "$FLAG"
    log INFO "reset-world.flag consumed"
  else
    log INFO "No reset-world.flag detected, skipping world reset"
  fi
}
