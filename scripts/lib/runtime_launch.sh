# shellcheck shell=bash

run_server() {
  cleanup_rcon_lock_on_boot

  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" &
  else
    log WARN "setsid not found; server signal propagation is limited to the launcher process"
    "$@" &
  fi
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

runtime() {
  log INFO "Starting runtime (TYPE=${TYPE})"
  run_phase_hooks "pre-runtime"

  case "${TYPE}" in
    fabric)
      log INFO "Launching Fabric server (single JVM)"
      run_server java @"${JVM_ARGS_FILE}" \
        -jar "${DATA_DIR}/fabric-server-launch.jar" nogui
      ;;

    quilt|paper|purpur|spigot|mohist|taiyitist|youer|vanilla)
      log INFO "Launching ${TYPE} server (single JVM)"
      run_server java @"${JVM_ARGS_FILE}" \
        -jar "${DATA_DIR}/server.jar" nogui
      ;;

    forge|neoforge)
      cd "${DATA_DIR}" || die "Failed to cd to DATA_DIR: ${DATA_DIR}"
      [[ -f "./run.sh" ]] || die "${TYPE} runtime not installed (run.sh missing)"
      chmod +x ./run.sh || die "Failed to make ./run.sh executable for ${TYPE} runtime"
      [[ -x "./run.sh" ]] || die "./run.sh is not executable for ${TYPE} runtime"

      log INFO "Launching ${TYPE} server"
      run_server bash -c 'exec "$@"' "${TYPE}-run.sh" ./run.sh nogui
      ;;

    velocity)
      [[ -f "${DATA_DIR}/velocity.jar" ]] || die "velocity.jar not found at ${DATA_DIR}/velocity.jar"
      cd "${DATA_DIR}" || die "Failed to cd to DATA_DIR: ${DATA_DIR}"
      log INFO "Launching Velocity server"
      run_server java @"${JVM_ARGS_FILE}" -jar "${DATA_DIR}/velocity.jar"
      ;;

    *)
      die "Unknown TYPE: ${TYPE}"
      ;;
  esac
}
