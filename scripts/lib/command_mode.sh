# shellcheck shell=bash

# shellcheck disable=SC2034  # Read by entrypoint.sh after command-mode handling.
COMMAND_MODE_SHIFT=0

handle_command_mode() {
  COMMAND_MODE_SHIFT=0

  case "${1:-run}" in
    run)
      COMMAND_MODE_SHIFT=1
      ;;
    install-only)
      # shellcheck disable=SC2034  # Read by main in entrypoint.sh after install.
      INSTALL_ONLY=true
      COMMAND_MODE_SHIFT=1
      ;;
    rcon)
      shift
      rcon_exec "$@"
      exit $?
      ;;
    rcon-say)
      shift
      rcon_say "$@"
      exit $?
      ;;
    rcon-stop)
      if ! rcon_stop_once; then
        log WARN "[shutdown] rcon-stop command failed; exiting 0 for Kubernetes preStop compatibility"
      fi
      exit 0
      ;;
  esac
}
