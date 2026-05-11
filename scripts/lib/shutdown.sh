# shellcheck shell=bash

cleanup_rcon_lock_on_boot() {
  # Remove stale lock from previous container runs (best-effort)
  rm -rf "${RCON_STOP_LOCK}" 2>/dev/null || true
}

acquire_rcon_stop_lock() {
  mkdir "${RCON_STOP_LOCK}" 2>/dev/null
}

rcon_stop_once() {
  # Prevent re-entrance within same process
  if [ "${RCON_STOP_IN_PROGRESS}" = "1" ]; then
    return "${RCON_STOP_RESULT}"
  fi

  # Prevent double execution across preStop/trap (but allow first run)
  if ! acquire_rcon_stop_lock; then
    log INFO "rcon_stop already running (lock exists), skipping"
    return "${RCON_STOP_RESULT}"
  fi

  # Mark as in-progress ONLY after acquiring the lock
  RCON_STOP_IN_PROGRESS=1

  rcon_stop
  RCON_STOP_RESULT=$?
  return "${RCON_STOP_RESULT}"
}
