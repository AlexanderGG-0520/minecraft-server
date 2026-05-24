# shellcheck shell=bash

cleanup_rcon_lock_on_boot() {
  # Remove stale lock from previous container runs (best-effort)
  if [[ -e "${RCON_STOP_LOCK}" ]]; then
    log WARN "[shutdown] removing stale rcon_stop lock on boot: ${RCON_STOP_LOCK}"
    rm -rf "${RCON_STOP_LOCK}" 2>/dev/null || true
  fi
}

rcon_stop_result_file() {
  printf '%s/result' "${RCON_STOP_LOCK}"
}

rcon_stop_owner_file() {
  printf '%s/owner' "${RCON_STOP_LOCK}"
}

acquire_rcon_stop_lock() {
  mkdir "${RCON_STOP_LOCK}" 2>/dev/null
}

initialize_rcon_stop_result() {
  local result_file
  local owner_file

  result_file="$(rcon_stop_result_file)"
  owner_file="$(rcon_stop_owner_file)"

  rm -f "${result_file}" 2>/dev/null || {
    log WARN "[shutdown] failed to remove stale rcon_stop result: ${result_file}"
    return 1
  }

  printf 'pid=%s ppid=%s started=%s\n' "$$" "${PPID:-unknown}" "$(date +%s)" > "${owner_file}" 2>/dev/null || {
    log WARN "[shutdown] failed to write rcon_stop owner file: ${owner_file}"
    return 1
  }
}

write_rcon_stop_result() {
  local result="$1"
  local result_file
  local result_dir
  local tmp

  result_file="$(rcon_stop_result_file)"
  result_dir="$(dirname "${result_file}")"

  if [[ ! -d "${result_dir}" ]]; then
    log WARN "[shutdown] rcon_stop result directory does not exist: ${result_dir}"
    return 1
  fi

  tmp="$(mktemp "${result_dir}/.result.XXXXXX")" || {
    log WARN "[shutdown] failed to create rcon_stop result temp file in ${result_dir}"
    return 1
  }

  printf '%s\n' "${result}" > "${tmp}" 2>/dev/null || {
    log WARN "[shutdown] failed to write rcon_stop result temp file: ${tmp}"
    safe_rm_f "${tmp}" 2>/dev/null || true
    return 1
  }
  safe_mv_f "${tmp}" "${result_file}" 2>/dev/null || {
    log WARN "[shutdown] failed to move rcon_stop result temp file into place: ${tmp} -> ${result_file}"
    safe_rm_f "${tmp}" 2>/dev/null || true
    return 1
  }
  chmod 0644 -- "${result_file}" 2>/dev/null || {
    log WARN "[shutdown] failed to set readable permissions on rcon_stop result file: ${result_file}"
    return 1
  }
}

read_rcon_stop_result() {
  local result_file
  local owner_file
  local result

  result_file="$(rcon_stop_result_file)"
  owner_file="$(rcon_stop_owner_file)"

  if [[ ! -f "${owner_file}" ]]; then
    if [[ -f "${result_file}" ]]; then
      log WARN "[shutdown] rcon_stop lock has no owner file; ignoring any result as stale: ${RCON_STOP_LOCK}"
    else
      log INFO "[shutdown] rcon_stop lock has no owner file yet: ${RCON_STOP_LOCK}"
    fi
    return 1
  fi

  if [[ ! -f "${result_file}" ]]; then
    log INFO "[shutdown] rcon_stop result not available yet: ${result_file}"
    return 1
  fi

  IFS= read -r result < "${result_file}" || return 1
  if [[ "${result}" =~ ^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]]; then
    log INFO "[shutdown] read shared rcon_stop result=${result} from ${result_file}"
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

  log INFO "[shutdown] waiting for shared rcon_stop result started (timeout: ${timeout}s)"
  while (( elapsed < timeout )); do
    if read_rcon_stop_result; then
      log INFO "[shutdown] shared rcon_stop result became available after ${elapsed}s"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if read_rcon_stop_result; then
    log INFO "[shutdown] shared rcon_stop result became available at timeout boundary"
    return 0
  fi

  log WARN "[shutdown] timed out waiting for shared rcon_stop result after ${timeout}s"
  return 1
}

signal_server_process() {
  local signal="$1"

  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    log WARN "[shutdown] sending ${signal} to server pid ${SERVER_PID}"
    kill "-${signal}" "${SERVER_PID}" 2>/dev/null || true
    log WARN "[shutdown] sending ${signal} to server process group -${SERVER_PID}"
    kill "-${signal}" "-${SERVER_PID}" 2>/dev/null || true
  else
    log WARN "[shutdown] no live SERVER_PID available for ${signal} fallback"
  fi
}

rcon_stop_once() {
  # Prevent re-entrance within same process
  if [ "${RCON_STOP_IN_PROGRESS}" = "1" ]; then
    log INFO "[shutdown] rcon_stop already in progress in this process; returning result=${RCON_STOP_RESULT}"
    return "${RCON_STOP_RESULT}"
  fi

  # Prevent double execution across preStop/trap (but allow first run)
  if ! acquire_rcon_stop_lock; then
    log INFO "[shutdown] rcon_stop lock exists; another process is running or completed rcon_stop: ${RCON_STOP_LOCK}"
    if read_rcon_stop_result; then
      log INFO "[shutdown] using existing shared rcon_stop result=${RCON_STOP_RESULT}"
      return "${RCON_STOP_RESULT}"
    fi

    if wait_for_rcon_stop_result "${RCON_STOP_LOCK_WAIT_TIMEOUT}"; then
      log INFO "[shutdown] using waited shared rcon_stop result=${RCON_STOP_RESULT}"
      return "${RCON_STOP_RESULT}"
    fi

    log WARN "[shutdown] rcon_stop lock exists but no shared result was readable; treating as failure so shutdown can fall back to signaling the server process"
    RCON_STOP_RESULT=1
    return "${RCON_STOP_RESULT}"
  fi

  # Mark as in-progress ONLY after acquiring the lock
  RCON_STOP_IN_PROGRESS=1
  log INFO "[shutdown] acquired rcon_stop lock as owner pid=$$: ${RCON_STOP_LOCK}"
  initialize_rcon_stop_result || log WARN "[shutdown] rcon_stop result initialization failed; continuing with direct rcon_stop"

  log INFO "[shutdown] rcon_stop owner executing rcon_stop"
  rcon_stop
  RCON_STOP_RESULT=$?
  log INFO "[shutdown] rcon_stop owner completed with result=${RCON_STOP_RESULT}"
  if write_rcon_stop_result "${RCON_STOP_RESULT}"; then
    log INFO "[shutdown] wrote shared rcon_stop result=${RCON_STOP_RESULT} to $(rcon_stop_result_file)"
  else
    log WARN "[shutdown] failed to write rcon_stop result to $(rcon_stop_result_file)"
  fi
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
    log INFO "[shutdown] invoking rcon_stop_once"
    if ! rcon_stop_once; then
      log WARN "[shutdown] RCON stop failed or unavailable, sending TERM to server process"
      signal_server_process TERM
    else
      log INFO "[shutdown] rcon_stop_once completed successfully"
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
