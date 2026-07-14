# shellcheck shell=bash

shutdown_rcon_command_budget_seconds() {
  validate_shutdown_numeric_value shutdown-budget RCON_RETRIES positive "${RCON_RETRIES:-}" || return 1
  validate_shutdown_numeric_value shutdown-budget RCON_TIMEOUT positive "${RCON_TIMEOUT:-}" || return 1
  validate_shutdown_numeric_value shutdown-budget RCON_RETRY_DELAY nonnegative "${RCON_RETRY_DELAY:-}" || return 1
  printf '%s\n' "$((RCON_RETRIES * RCON_TIMEOUT + (RCON_RETRIES - 1) * RCON_RETRY_DELAY))"
}

shutdown_rcon_first_attempt_success_seconds() {
  validate_shutdown_numeric_value shutdown-budget SHUTDOWN_SAVE_WAIT_SECONDS nonnegative "${SHUTDOWN_SAVE_WAIT_SECONDS:-}" || return 1
  validate_shutdown_numeric_value shutdown-budget STOP_SERVER_ANNOUNCE_DELAY nonnegative "${STOP_SERVER_ANNOUNCE_DELAY:-}" || return 1
  local announcement=0
  if (( STOP_SERVER_ANNOUNCE_DELAY > 0 )); then
    announcement=$((STOP_SERVER_ANNOUNCE_DELAY + RCON_TIMEOUT))
  fi
  printf '%s\n' "$((announcement + 3 * RCON_TIMEOUT + SHUTDOWN_SAVE_WAIT_SECONDS))"
}

shutdown_rcon_flush_fallback_success_seconds() {
  validate_shutdown_numeric_value shutdown-budget SHUTDOWN_SAVE_WAIT_SECONDS nonnegative "${SHUTDOWN_SAVE_WAIT_SECONDS:-}" || return 1
  printf '%s\n' "$((4 * RCON_TIMEOUT + SHUTDOWN_SAVE_WAIT_SECONDS))"
}

shutdown_rcon_all_attempts_fail_seconds() {
  local command_budget
  command_budget="$(shutdown_rcon_command_budget_seconds)" || return 1
  printf '%s\n' "$((4 * command_budget))"
}

shutdown_rcon_stop_budget_seconds() {
  validate_shutdown_numeric_value shutdown-budget STOP_SERVER_ANNOUNCE_DELAY nonnegative "${STOP_SERVER_ANNOUNCE_DELAY:-}" || return 1
  validate_shutdown_numeric_value shutdown-budget SHUTDOWN_SAVE_WAIT_SECONDS nonnegative "${SHUTDOWN_SAVE_WAIT_SECONDS:-}" || return 1
  local command_budget announcement=0
  command_budget="$(shutdown_rcon_command_budget_seconds)" || return 1
  if (( STOP_SERVER_ANNOUNCE_DELAY > 0 )); then
    # tellraw may fail and invoke the say fallback before the configured delay.
    announcement=$((STOP_SERVER_ANNOUNCE_DELAY + 2 * command_budget))
  fi
  # citizens save, flush, fallback save, and stop can each consume a full retry budget.
  # The save wait is included because the fallback save can succeed on its final attempt.
  printf '%s\n' "$((announcement + 4 * command_budget + SHUTDOWN_SAVE_WAIT_SECONDS))"
}

shutdown_graceful_budget_seconds() {
  validate_shutdown_numeric_value shutdown-budget RCON_STOP_LOCK_WAIT_TIMEOUT nonnegative "${RCON_STOP_LOCK_WAIT_TIMEOUT:-}" || return 1
  validate_shutdown_numeric_value shutdown-budget SHUTDOWN_WAIT_TIMEOUT nonnegative "${SHUTDOWN_WAIT_TIMEOUT:-}" || return 1
  validate_shutdown_numeric_value shutdown-budget SHUTDOWN_TERM_WAIT nonnegative "${SHUTDOWN_TERM_WAIT:-}" || return 1
  local rcon_stop_budget shutdown_phase_budget
  rcon_stop_budget="$(shutdown_rcon_stop_budget_seconds)" || return 1
  shutdown_phase_budget="${rcon_stop_budget}"
  if (( RCON_STOP_LOCK_WAIT_TIMEOUT > shutdown_phase_budget )); then
    shutdown_phase_budget="${RCON_STOP_LOCK_WAIT_TIMEOUT}"
  fi
  printf '%s\n' "$((shutdown_phase_budget + SHUTDOWN_WAIT_TIMEOUT + SHUTDOWN_TERM_WAIT))"
}

shutdown_recommended_grace_seconds() {
  local safety_margin_seconds=21
  local shutdown_budget
  shutdown_budget="$(shutdown_graceful_budget_seconds)" || return 1
  printf '%s\n' "$((shutdown_budget + safety_margin_seconds))"
}
