#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_fake_rcon() {
  local bin_dir="$1"

  mkdir -p "${bin_dir}"
  cat > "${bin_dir}/rcon-cli" <<'RCON'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${TMP_DIR}/commands.txt"
if [[ "$*" == *" save-all flush" && "${RCON_FAIL_FLUSH:-0}" == "1" ]]; then
  exit 1
fi
if [[ "$*" == *" save-all" && "$*" != *" save-all flush" && "${RCON_FAIL_SAVE_ALL:-0}" == "1" ]]; then
  exit 1
fi
if [[ "$*" == *" stop" && "${RCON_FAIL_STOP:-0}" == "1" ]]; then
  exit 1
fi
if [[ "${RCON_FAIL_GENERIC:-0}" == "1" ]]; then
  exit 1
fi
exit 0
RCON
  chmod +x "${bin_dir}/rcon-cli"

  cat > "${bin_dir}/mcrcon" <<'MCRCON'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${TMP_DIR}/commands.txt"
if [[ "$*" == *" save-all flush" && "${RCON_FAIL_FLUSH:-0}" == "1" ]]; then
  exit 1
fi
if [[ "$*" == *" save-all" && "$*" != *" save-all flush" && "${RCON_FAIL_SAVE_ALL:-0}" == "1" ]]; then
  exit 1
fi
if [[ "$*" == *" stop" && "${RCON_FAIL_STOP:-0}" == "1" ]]; then
  exit 1
fi
if [[ "${RCON_FAIL_GENERIC:-0}" == "1" ]]; then
  exit 1
fi
exit 0
MCRCON
  chmod +x "${bin_dir}/mcrcon"
}

setup_rcon_env() {
  local name="$1"

  TMP_DIR="${tmp}/${name}"
  export TMP_DIR
  mkdir -p "${TMP_DIR}/bin"
  make_fake_rcon "${TMP_DIR}/bin"

  PATH="${TMP_DIR}/bin:${ORIGINAL_PATH}"
  DATA_DIR="${TMP_DIR}/data"
  ENABLE_RCON=true
  RCON_HOST=127.0.0.1
  RCON_PORT=25575
  RCON_PASSWORD=secret
  RCON_TIMEOUT=1
  RCON_RETRIES=1
  RCON_RETRY_DELAY=0
  SHUTDOWN_SAVE_WAIT_SECONDS=0
  STOP_SERVER_ANNOUNCE_DELAY=0
  export PATH DATA_DIR ENABLE_RCON RCON_HOST RCON_PORT RCON_PASSWORD
  export RCON_TIMEOUT RCON_RETRIES RCON_RETRY_DELAY SHUTDOWN_SAVE_WAIT_SECONDS
  export STOP_SERVER_ANNOUNCE_DELAY

  mkdir -p "${DATA_DIR}/plugins/Citizens"
  touch "${DATA_DIR}/plugins/Citizens/saves.yml"
  : > "${TMP_DIR}/commands.txt"
}

assert_command() {
  local line="$1"
  local expected="$2"
  local actual

  actual="$(sed -n "${line}p" "${TMP_DIR}/commands.txt")"
  [[ "${actual}" == "${expected}" ]] || {
    printf 'expected command %s: %s\nactual: %s\n' "${line}" "${expected}" "${actual}" >&2
    return 1
  }
}

assert_no_command() {
  local line="$1"
  local actual

  actual="$(sed -n "${line}p" "${TMP_DIR}/commands.txt")"
  [[ -z "${actual}" ]] || {
    printf 'expected no command %s\nactual: %s\n' "${line}" "${actual}" >&2
    return 1
  }
}

assert_log_contains() {
  local log_file="$1"
  local expected="$2"

  grep -F "${expected}" "${log_file}" >/dev/null || {
    printf 'expected log to contain: %s\n' "${expected}" >&2
    printf 'actual log:\n' >&2
    sed 's/^/  /' "${log_file}" >&2
    return 1
  }
}

run_rcon_stop_success_smoke() {
  setup_rcon_env "success"
  rcon_stop
  assert_command 1 "--host 127.0.0.1 --port 25575 --password secret citizens save"
  assert_command 2 "--host 127.0.0.1 --port 25575 --password secret save-all flush"
  assert_command 3 "--host 127.0.0.1 --port 25575 --password secret stop"
  assert_no_command 4
}

run_rcon_stop_fallback_smoke() {
  setup_rcon_env "fallback"
  RCON_FAIL_FLUSH=1
  export RCON_FAIL_FLUSH
  rcon_stop
  assert_command 2 "--host 127.0.0.1 --port 25575 --password secret save-all flush"
  assert_command 3 "--host 127.0.0.1 --port 25575 --password secret save-all"
  assert_command 4 "--host 127.0.0.1 --port 25575 --password secret stop"
  unset RCON_FAIL_FLUSH
}

run_rcon_stop_save_failure_smoke() {
  setup_rcon_env "save-failure"
  RCON_FAIL_FLUSH=1
  RCON_FAIL_SAVE_ALL=1
  export RCON_FAIL_FLUSH RCON_FAIL_SAVE_ALL
  rcon_stop
  assert_command 2 "--host 127.0.0.1 --port 25575 --password secret save-all flush"
  assert_command 3 "--host 127.0.0.1 --port 25575 --password secret save-all"
  assert_command 4 "--host 127.0.0.1 --port 25575 --password secret stop"
  unset RCON_FAIL_FLUSH RCON_FAIL_SAVE_ALL
}

run_rcon_stop_stop_failure_smoke() {
  setup_rcon_env "stop-failure"
  RCON_FAIL_STOP=1
  export RCON_FAIL_STOP
  set +e
  rcon_stop
  local rc=$?
  set -e
  [[ "${rc}" -ne 0 ]]
  assert_command 3 "--host 127.0.0.1 --port 25575 --password secret stop"
  unset RCON_FAIL_STOP
}

run_rcon_exec_rcon_cli_smoke() {
  setup_rcon_env "rcon-cli-exec"
  set +e
  rcon_exec "list"
  local rc=$?
  set -e
  [[ "${rc}" -eq 0 ]]
  assert_command 1 "--host 127.0.0.1 --port 25575 --password secret list"

  RCON_FAIL_GENERIC=1
  export RCON_FAIL_GENERIC
  : > "${TMP_DIR}/commands.txt"
  set +e
  rcon_exec "list"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]]
  assert_command 1 "--host 127.0.0.1 --port 25575 --password secret list"
  unset RCON_FAIL_GENERIC
}

run_rcon_exec_mcrcon_smoke() {
  setup_rcon_env "mcrcon-exec"
  rm -f "${TMP_DIR}/bin/rcon-cli"
  PATH="${TMP_DIR}/bin:${ORIGINAL_PATH}"
  export PATH

  set +e
  rcon_exec "list"
  local rc=$?
  set -e
  [[ "${rc}" -eq 0 ]]
  assert_command 1 "-H 127.0.0.1 -P 25575 -p secret list"

  RCON_FAIL_GENERIC=1
  export RCON_FAIL_GENERIC
  : > "${TMP_DIR}/commands.txt"
  set +e
  rcon_exec "list"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]]
  assert_command 1 "-H 127.0.0.1 -P 25575 -p secret list"
  unset RCON_FAIL_GENERIC
}

run_invalid_save_wait_smoke() {
  setup_rcon_env "invalid-save-wait"
  SHUTDOWN_SAVE_WAIT_SECONDS=invalid
  export SHUTDOWN_SAVE_WAIT_SECONDS
  set +e
  rcon_stop
  local rc=$?
  set -e
  [[ "${rc}" -ne 0 ]]
}

run_invalid_announce_delay_smoke() {
  setup_rcon_env "invalid-announce-delay"
  local log_file="${TMP_DIR}/invalid-announce-delay.log"

  STOP_SERVER_ANNOUNCE_DELAY=invalid
  export STOP_SERVER_ANNOUNCE_DELAY
  set +e
  rcon_stop > "${log_file}" 2>&1
  local rc=$?
  set -e

  [[ "${rc}" -ne 0 ]]
  assert_log_contains "${log_file}" "STOP_SERVER_ANNOUNCE_DELAY must be a non-negative integer, got: invalid"
  if grep -F "unbound variable" "${log_file}"; then
    return 1
  fi
  if grep -F "syntax error: operand expected" "${log_file}"; then
    return 1
  fi
  [[ ! -s "${TMP_DIR}/commands.txt" ]]
}

run_invalid_rcon_exec_smoke() {
  setup_rcon_env "invalid-rcon-exec"
  local log_file="${TMP_DIR}/invalid-rcon-exec.log"

  RCON_RETRIES=invalid
  export RCON_RETRIES
  set +e
  rcon_exec list > "${log_file}" 2>&1
  local rc=$?
  set -e

  [[ "${rc}" -ne 0 ]]
  assert_log_contains "${log_file}" "RCON_RETRIES must be a positive integer, got: invalid"
  if grep -F "unbound variable" "${log_file}"; then
    return 1
  fi
  [[ ! -s "${TMP_DIR}/commands.txt" ]]
}

run_invalid_wait_smokes() {
  setup_rcon_env "invalid-waits"
  local log_file="${TMP_DIR}/invalid-waits.log"

  set +e
  wait_for_rcon_stop_result invalid > "${log_file}" 2>&1
  local lock_rc=$?
  SHUTDOWN_WAIT_TIMEOUT=invalid
  wait_for_server_exit "${SHUTDOWN_WAIT_TIMEOUT}" >> "${log_file}" 2>&1
  local shutdown_rc=$?
  SHUTDOWN_TERM_WAIT=invalid
  wait_for_server_exit "${SHUTDOWN_TERM_WAIT}" SHUTDOWN_TERM_WAIT >> "${log_file}" 2>&1
  local term_rc=$?
  set -e

  [[ "${lock_rc}" -ne 0 ]]
  [[ "${shutdown_rc}" -ne 0 ]]
  [[ "${term_rc}" -ne 0 ]]
  assert_log_contains "${log_file}" "RCON_STOP_LOCK_WAIT_TIMEOUT must be a non-negative integer, got: invalid"
  assert_log_contains "${log_file}" "SHUTDOWN_WAIT_TIMEOUT must be a non-negative integer, got: invalid"
  assert_log_contains "${log_file}" "SHUTDOWN_TERM_WAIT must be a non-negative integer, got: invalid"
  if grep -F "unbound variable" "${log_file}"; then
    return 1
  fi
}

run_invalid_ready_delay_smoke() {
  setup_rcon_env "invalid-ready-delay"
  local log_file="${TMP_DIR}/invalid-ready-delay.log"

  READY_DELAY=invalid
  export READY_DELAY
  set +e
  run_server bash -c 'exit 0' > "${log_file}" 2>&1
  local rc=$?
  set -e

  [[ "${rc}" -ne 0 ]]
  assert_log_contains "${log_file}" "READY_DELAY must be a non-negative integer, got: invalid"
  if grep -F "unbound variable" "${log_file}"; then
    return 1
  fi
}

run_invalid_shutdown_fallback_smoke() {
  setup_rcon_env "invalid-shutdown-fallback"
  local log_file="${TMP_DIR}/invalid-shutdown-fallback.log"

  SERVER_PID=4242
  TYPE=PAPER
  STOP_SERVER_ANNOUNCE_DELAY=invalid
  SHUTDOWN_WAIT_TIMEOUT=0
  SHUTDOWN_TERM_WAIT=0
  RCON_STOP_LOCK="${TMP_DIR}/lock"
  RCON_STOP_IN_PROGRESS=0
  RCON_STOP_RESULT=1
  export TYPE STOP_SERVER_ANNOUNCE_DELAY SHUTDOWN_WAIT_TIMEOUT SHUTDOWN_TERM_WAIT
  signal_server_process() { printf '%s\n' "$*" >> "${TMP_DIR}/signals.txt"; }
  wait_for_server_exit() { return 0; }

  set +e
  ( graceful_shutdown ) > "${log_file}" 2>&1
  set -e

  assert_log_contains "${log_file}" "STOP_SERVER_ANNOUNCE_DELAY must be a non-negative integer, got: invalid"
  assert_log_contains "${log_file}" "RCON stop failed or unavailable, sending TERM to server process"
  [[ "$(cat "${TMP_DIR}/signals.txt")" == "TERM" ]]
  if grep -F "unbound variable" "${log_file}"; then
    return 1
  fi
  unset -f signal_server_process wait_for_server_exit
}

run_shutdown_timeout_phase_log_smoke() {
  setup_rcon_env "shutdown-timeout-phase-log"
  local log_file="${TMP_DIR}/shutdown-timeout-phase.log"

  SERVER_PID=4242
  TYPE=PAPER
  ENABLE_RCON=false
  SHUTDOWN_WAIT_TIMEOUT=0
  SHUTDOWN_TERM_WAIT=0
  export TYPE ENABLE_RCON SHUTDOWN_WAIT_TIMEOUT SHUTDOWN_TERM_WAIT
  signal_server_process() { printf '%s\n' "$*" >> "${TMP_DIR}/signals.txt"; }
  wait_for_server_exit() { return 1; }

  set +e
  ( graceful_shutdown ) > "${log_file}" 2>&1
  set -e

  assert_log_contains "${log_file}" "SHUTDOWN_WAIT_TIMEOUT exhausted, sending TERM"
  assert_log_contains "${log_file}" "SHUTDOWN_TERM_WAIT exhausted, forcing KILL"
  [[ "$(cat "${TMP_DIR}/signals.txt")" == $'TERM\nTERM\nKILL' ]]
  unset -f signal_server_process wait_for_server_exit
}

run_shutdown_clears_readiness_smoke() {
  setup_rcon_env "shutdown-clears-readiness"
  local log_file="${TMP_DIR}/shutdown-clears-readiness.log"

  touch "${DATA_DIR}/.ready"
  TYPE=PAPER
  SHUTDOWN_WAIT_TIMEOUT=0
  export TYPE SHUTDOWN_WAIT_TIMEOUT
  rcon_stop_once() { return 0; }
  wait_for_server_exit() { return 0; }

  ( graceful_shutdown ) > "${log_file}" 2>&1

  [[ ! -e "${DATA_DIR}/.ready" ]]
  assert_log_contains "${log_file}" "[shutdown] begin"
  assert_log_contains "${log_file}" "[shutdown] end"
  unset -f rcon_stop_once wait_for_server_exit
}

run_lock_owner_success_smoke() {
  setup_rcon_env "lock-owner-success"
  local log_file="${TMP_DIR}/lock-owner.log"

  RCON_STOP_LOCK="${TMP_DIR}/lock"
  RCON_STOP_LOCK_WAIT_TIMEOUT=1
  RCON_STOP_IN_PROGRESS=0
  RCON_STOP_RESULT=1

  rcon_stop_once > "${log_file}" 2>&1
  [[ "${RCON_STOP_RESULT}" -eq 0 ]]
  [[ "$(cat "${RCON_STOP_LOCK}/result")" == "0" ]]
  assert_command 2 "--host 127.0.0.1 --port 25575 --password secret save-all flush"
  assert_command 3 "--host 127.0.0.1 --port 25575 --password secret stop"
  assert_log_contains "${log_file}" "[shutdown] acquired rcon_stop lock as owner"
  assert_log_contains "${log_file}" "[shutdown] rcon_stop owner executing rcon_stop"
  assert_log_contains "${log_file}" "[shutdown] wrote shared rcon_stop result=0"
}

run_rcon_stop_command_mode_smoke() {
  local cmd_tmp="${tmp}/command-mode"

  mkdir -p "${cmd_tmp}"
  set +e
  ENABLE_RCON=false \
    RCON_STOP_LOCK="${cmd_tmp}/lock" \
    RCON_STOP_LOCK_WAIT_TIMEOUT=0 \
    DATA_DIR="${cmd_tmp}/data" \
    bash "${repo}/entrypoint.sh" rcon-stop >/dev/null 2>&1
  local rc=$?
  set -e
  [[ "${rc}" -eq 0 ]]
}

run_lock_result_coordination_smoke() {
  local lock_tmp="${tmp}/lock-result"
  local log_file="${lock_tmp}/waiter.log"

  mkdir -p "${lock_tmp}/lock"
  printf 'pid=test started=1\n' > "${lock_tmp}/lock/owner"
  (
    sleep 1
    printf '0\n' > "${lock_tmp}/lock/result"
  ) &
  local writer_pid=$!

  RCON_STOP_LOCK="${lock_tmp}/lock"
  RCON_STOP_LOCK_WAIT_TIMEOUT=5
  RCON_STOP_IN_PROGRESS=0
  RCON_STOP_RESULT=1
  rcon_stop() {
    printf 'unexpected parent rcon_stop call\n' >&2
    return 9
  }

  rcon_stop_once > "${log_file}" 2>&1
  [[ "${RCON_STOP_RESULT}" -eq 0 ]]
  wait "${writer_pid}"
  assert_log_contains "${log_file}" "[shutdown] rcon_stop lock exists; another process is running or completed rcon_stop"
  assert_log_contains "${log_file}" "[shutdown] waiting for shared rcon_stop result started"
  assert_log_contains "${log_file}" "[shutdown] using waited shared rcon_stop result=0"
}

run_lock_missing_result_smoke() {
  local lock_tmp="${tmp}/lock-missing-result"
  local log_file="${lock_tmp}/missing.log"

  mkdir -p "${lock_tmp}/lock"
  printf 'pid=test started=1\n' > "${lock_tmp}/lock/owner"

  RCON_STOP_LOCK="${lock_tmp}/lock"
  RCON_STOP_LOCK_WAIT_TIMEOUT=0
  RCON_STOP_IN_PROGRESS=0
  RCON_STOP_RESULT=1

  set +e
  rcon_stop_once > "${log_file}" 2>&1
  local rc=$?
  set -e

  [[ "${rc}" -ne 0 ]]
  [[ "${RCON_STOP_RESULT}" -eq 1 ]]
  assert_log_contains "${log_file}" "[shutdown] timed out waiting for shared rcon_stop result after 0s"
  assert_log_contains "${log_file}" "[shutdown] rcon_stop lock exists but no shared result was readable"
}

run_stale_result_smoke() {
  local lock_tmp="${tmp}/stale-result"
  local log_file="${lock_tmp}/stale.log"

  mkdir -p "${lock_tmp}/lock"
  printf '0\n' > "${lock_tmp}/lock/result"

  RCON_STOP_LOCK="${lock_tmp}/lock"
  RCON_STOP_LOCK_WAIT_TIMEOUT=0
  RCON_STOP_IN_PROGRESS=0
  RCON_STOP_RESULT=1

  set +e
  rcon_stop_once > "${log_file}" 2>&1
  local rc=$?
  set -e

  [[ "${rc}" -ne 0 ]]
  [[ "${RCON_STOP_RESULT}" -eq 1 ]]
  assert_log_contains "${log_file}" "[shutdown] rcon_stop lock has no owner file; ignoring any result as stale"
}

run_signal_group_smoke() {
  local sig_tmp="${tmp}/signal-group"
  mkdir -p "${sig_tmp}"
  local calls="${sig_tmp}/kill-calls"
  kill() { printf '%s\n' "$*" >> "${calls}"; }
  SERVER_PID=4242
  signal_server_process TERM
  test "$(sed -n '1p' "${calls}")" = '-0 4242'
  test "$(sed -n '2p' "${calls}")" = '-TERM 4242'
  test "$(sed -n '3p' "${calls}")" = '-TERM -4242'
  unset -f kill
}

ORIGINAL_PATH="${PATH}"
cd "${repo}"
source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh
source ./scripts/lib/numeric_validation.sh
source ./scripts/lib/rcon.sh
source ./scripts/lib/shutdown.sh
source ./scripts/lib/runtime_launch.sh
json_escape() {
  local s="$*"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "${s}"
}

run_rcon_stop_success_smoke
run_rcon_stop_fallback_smoke
run_rcon_stop_save_failure_smoke
run_rcon_stop_stop_failure_smoke
run_rcon_exec_rcon_cli_smoke
run_rcon_exec_mcrcon_smoke
run_lock_owner_success_smoke
run_rcon_stop_command_mode_smoke
run_invalid_save_wait_smoke
run_invalid_announce_delay_smoke
run_invalid_rcon_exec_smoke
run_invalid_wait_smokes
run_invalid_ready_delay_smoke
run_lock_result_coordination_smoke
source ./scripts/lib/rcon.sh
run_lock_missing_result_smoke
run_stale_result_smoke
run_signal_group_smoke
run_invalid_shutdown_fallback_smoke
run_shutdown_timeout_phase_log_smoke
run_shutdown_clears_readiness_smoke
