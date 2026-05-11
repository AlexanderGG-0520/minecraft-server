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

wait_for_server_exit() {
  local timeout="$1"
  local elapsed=0

  while [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; do
    if (( elapsed >= timeout )); then
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  return 0
}

graceful_shutdown() {
  log INFO "[shutdown] begin"

  if [[ "${TYPE}" == "velocity" ]]; then
    log INFO "[shutdown] velocity detected, skipping rcon_stop"
  else
    if ! rcon_stop_once; then
      log WARN "[shutdown] RCON stop failed or unavailable, sending TERM to server process"
      if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
        kill -TERM "${SERVER_PID}" 2>/dev/null || true
      fi
    fi
  fi

  log INFO "[shutdown] waiting for server process (timeout: ${SHUTDOWN_WAIT_TIMEOUT}s)"
  if wait_for_server_exit "${SHUTDOWN_WAIT_TIMEOUT}"; then
    log INFO "[shutdown] server process exited"
    log INFO "[shutdown] end"
    exit 0
  fi

  log WARN "[shutdown] timeout exceeded, sending TERM"
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill -TERM "${SERVER_PID}" 2>/dev/null || true
  fi

  if wait_for_server_exit "${SHUTDOWN_TERM_WAIT}"; then
    log INFO "[shutdown] server process exited after TERM"
    log INFO "[shutdown] end"
    exit 0
  fi

  log WARN "[shutdown] forcing kill"
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill -KILL "${SERVER_PID}" 2>/dev/null || true
  fi

  log INFO "[shutdown] end"
  exit 0
}
