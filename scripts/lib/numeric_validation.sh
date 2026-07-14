# shellcheck shell=bash

is_safe_nonnegative_integer() {
  local value="${1:-}"

  [[ "${value}" =~ ^(0|[1-9][0-9]*)$ ]] || return 1

  if (( ${#value} < 10 )); then
    return 0
  fi

  (( ${#value} == 10 && 10#${value} <= 2147483647 ))
}

is_safe_positive_integer() {
  local value="${1:-}"

  [[ "${value}" != "0" ]] && is_safe_nonnegative_integer "${value}"
}

validate_shutdown_numeric_value() {
  local context="$1"
  local variable_name="$2"
  local rule="$3"
  local value="$4"

  case "${rule}" in
    nonnegative)
      is_safe_nonnegative_integer "${value}" && return 0
      log ERROR "[${context}] ${variable_name} must be a non-negative integer, got: ${value:-<empty>}"
      ;;
    positive)
      is_safe_positive_integer "${value}" && return 0
      log ERROR "[${context}] ${variable_name} must be a positive integer, got: ${value:-<empty>}"
      ;;
    *)
      log ERROR "[${context}] unknown numeric validation rule for ${variable_name}"
      ;;
  esac

  return 1
}

validate_shutdown_numeric_config() {
  local context="$1"

  validate_shutdown_numeric_value "${context}" STOP_SERVER_ANNOUNCE_DELAY nonnegative "${STOP_SERVER_ANNOUNCE_DELAY:-}" || return 1
  validate_shutdown_numeric_value "${context}" SHUTDOWN_SAVE_WAIT_SECONDS nonnegative "${SHUTDOWN_SAVE_WAIT_SECONDS:-}" || return 1
  validate_shutdown_numeric_value "${context}" RCON_RETRIES positive "${RCON_RETRIES:-}" || return 1
  validate_shutdown_numeric_value "${context}" RCON_RETRY_DELAY nonnegative "${RCON_RETRY_DELAY:-}" || return 1
  validate_shutdown_numeric_value "${context}" RCON_TIMEOUT positive "${RCON_TIMEOUT:-}" || return 1
  validate_shutdown_numeric_value "${context}" SHUTDOWN_WAIT_TIMEOUT nonnegative "${SHUTDOWN_WAIT_TIMEOUT:-}" || return 1
  validate_shutdown_numeric_value "${context}" SHUTDOWN_TERM_WAIT nonnegative "${SHUTDOWN_TERM_WAIT:-}" || return 1
  validate_shutdown_numeric_value "${context}" RCON_STOP_LOCK_WAIT_TIMEOUT nonnegative "${RCON_STOP_LOCK_WAIT_TIMEOUT:-}" || return 1
  validate_shutdown_numeric_value "${context}" READY_DELAY nonnegative "${READY_DELAY:-}" || return 1
}
