# shellcheck shell=bash

cleanup_rcon_lock_on_boot() {
  # Remove stale lock from previous container runs (best-effort)
  rm -rf "${RCON_STOP_LOCK}" 2>/dev/null || true
}

rcon_stop_result_file() {
  printf '%s/result' "${RCON_STOP_LOCK}"
}

acquire_rcon_stop_lock() {
  mkdir "${RCON_STOP_LOCK}" 2>/dev/null
}

write_rcon_stop_result() {
  local result="$1"
  local result_file
  local tmp

  result_file="$(rcon_stop_result_file)"
  tmp="${result_file}.$$"

  printf '%s\n' "${result}" > "${tmp}" 2>/dev/null || return 1
  mv -f "${tmp}" "${result_file}" 2>/dev/null || {
    rm -f "${tmp}" 2>/dev/null || true
    return 1
  }
}

read_rcon_stop_result() {
  local result_file
  local result

  result_file="$(rcon_stop_result_file)"
  [[ -f "${result_file}" ]] || return 1

  IFS= read -r result < "${result_file}" || return 1
  if [[ "${result}" =~ ^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]]; then
    RCON_STOP_RESULT="${result}"
    return 0
  fi

  log WARN "[shutdown] invalid rcon_stop result file: ${result_file}"
  return 1
}

wait_for_rcon_stop_result() {
  local timeout="$1"
  local elapsed=0

  if [[ ! "${timeout}" =~ ^[0-9]+$ ]]; then
    log WARN "[shutdown] invalid RCON stop lock wait timeout: ${timeout}"
    return 1
  fi

  while (( elapsed < timeout )); do
    if read_rcon_stop_result; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  read_rcon_stop_result
}

signal_server_process() {
  local signal="$1"

  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill "-${signal}" "${SERVER_PID}" 2>/dev/null || true
    kill "-${signal}" "-${SERVER_PID}" 2>/dev/null || true
  fi
}

rcon_stop_once() {
  # Prevent re-entrance within same process
  if [ "${RCON_STOP_IN_PROGRESS}" = "1" ]; then
    return "${RCON_STOP_RESULT}"
  fi

  # Prevent double execution across preStop/trap (but allow first run)
  if ! acquire_rcon_stop_lock; then
    log INFO "rcon_stop already running or completed (lock exists)"
    if read_rcon_stop_result; then
      return "${RCON_STOP_RESULT}"
    fi

    log INFO "[shutdown] waiting for shared rcon_stop result (timeout: ${RCON_STOP_LOCK_WAIT_TIMEOUT}s)"
    if wait_for_rcon_stop_result "${RCON_STOP_LOCK_WAIT_TIMEOUT}"; then
      return "${RCON_STOP_RESULT}"
    fi

    log WARN "[shutdown] rcon_stop lock exists without result; assuming another shutdown path is handling stop"
    RCON_STOP_RESULT=0
    return 0
  fi

  # Mark as in-progress ONLY after acquiring the lock
  RCON_STOP_IN_PROGRESS=1

  rcon_stop
  RCON_STOP_RESULT=$?
  write_rcon_stop_result "${RCON_STOP_RESULT}" || log WARN "[shutdown] failed to write rcon_stop result"
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
      signal_server_process TERM
    fi
  fi

  log INFO "[shutdown] waiting for server process (timeout: ${SHUTDOWN_WAIT_TIMEOUT}s)"
  if wait_for_server_exit "${SHUTDOWN_WAIT_TIMEOUT}"; then
    log INFO "[shutdown] server process exited"
    log INFO "[shutdown] end"
    exit 0
  fi

  log WARN "[shutdown] timeout exceeded, sending TERM"
  signal_server_process TERM

  if wait_for_server_exit "${SHUTDOWN_TERM_WAIT}"; then
    log INFO "[shutdown] server process exited after TERM"
    log INFO "[shutdown] end"
    exit 0
  fi

  log WARN "[shutdown] forcing kill"
  signal_server_process KILL

  log INFO "[shutdown] end"
  exit 0
}
