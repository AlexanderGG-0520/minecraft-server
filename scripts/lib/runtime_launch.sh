# shellcheck shell=bash

run_server() {
  cleanup_rcon_lock_on_boot

  "$@" &
  SERVER_PID=$!

  local ready_delay="${READY_DELAY:-5}"
  [[ "$ready_delay" =~ ^[0-9]+$ ]] || die "READY_DELAY must be a non-negative integer"

  local elapsed=0
  while (( elapsed < ready_delay )); do
    if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
      local early_status=0
      wait "$SERVER_PID" || early_status=$?
      rm -f "${DATA_DIR}/.ready" 2>/dev/null || true
      return "$early_status"
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if kill -0 "${SERVER_PID}" 2>/dev/null; then
    touch "${DATA_DIR}/.ready" 2>/dev/null || log WARN "Failed to create readiness file: ${DATA_DIR}/.ready"
    log INFO "Readiness file created"
  fi

  local status=0
  wait "$SERVER_PID" || status=$?
  rm -f "${DATA_DIR}/.ready" 2>/dev/null || true
  return "$status"
}
