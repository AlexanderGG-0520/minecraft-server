#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cd "${repo}"
source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh
source ./scripts/lib/numeric_validation.sh
source ./scripts/lib/runtime.sh
source ./scripts/lib/preflight.sh

set_numeric_defaults() {
  STOP_SERVER_ANNOUNCE_DELAY=0
  SHUTDOWN_SAVE_WAIT_SECONDS=3
  RCON_RETRIES=5
  RCON_RETRY_DELAY=1
  RCON_TIMEOUT=5
  SHUTDOWN_WAIT_TIMEOUT=90
  SHUTDOWN_TERM_WAIT=10
  RCON_STOP_LOCK_WAIT_TIMEOUT=30
  READY_DELAY=5
  export STOP_SERVER_ANNOUNCE_DELAY SHUTDOWN_SAVE_WAIT_SECONDS RCON_RETRIES RCON_RETRY_DELAY
  export RCON_TIMEOUT SHUTDOWN_WAIT_TIMEOUT SHUTDOWN_TERM_WAIT RCON_STOP_LOCK_WAIT_TIMEOUT READY_DELAY
}

run_preflight() {
  local log_file="$1"
  preflight > "${log_file}" 2>&1
}

assert_preflight_success() {
  local name="$1"
  local log_file="${tmp}/${name}.log"

  set +e
  run_preflight "${log_file}"
  local rc=$?
  set -e
  [[ "${rc}" -eq 0 ]] || {
    sed 's/^/  /' "${log_file}" >&2
    return 1
  }
}

assert_preflight_failure() {
  local name="$1"
  local variable_name="$2"
  local expected_rule="$3"
  local value="$4"
  local log_file="${tmp}/${name}.log"

  set +e
  run_preflight "${log_file}"
  local rc=$?
  set -e
  [[ "${rc}" -ne 0 ]]
  local displayed_value="${value:-<empty>}"
  grep -F "[preflight] ${variable_name} must be a ${expected_rule} integer, got: ${displayed_value}" "${log_file}" >/dev/null
  ! grep -F "unbound variable" "${log_file}"
  ! grep -F "syntax error: operand expected" "${log_file}"
}

DATA_DIR="${tmp}/data"
mkdir -p "${DATA_DIR}"
EULA=true
TYPE=vanilla
ENABLE_RCON=false
export DATA_DIR EULA TYPE ENABLE_RCON

nonnegative_variables=(
  STOP_SERVER_ANNOUNCE_DELAY
  SHUTDOWN_SAVE_WAIT_SECONDS
  RCON_RETRY_DELAY
  SHUTDOWN_WAIT_TIMEOUT
  SHUTDOWN_TERM_WAIT
  RCON_STOP_LOCK_WAIT_TIMEOUT
  READY_DELAY
)
positive_variables=(
  RCON_RETRIES
  RCON_TIMEOUT
)
invalid_values=('' -1 invalid 1.5 5s ' 5' '5 ' 2147483648)

set_numeric_defaults
assert_preflight_success defaults

for variable_name in "${nonnegative_variables[@]}"; do
  set_numeric_defaults
  printf -v "${variable_name}" '%s' 0
  export "${variable_name}"
  assert_preflight_success "${variable_name}-zero"
done

for variable_name in "${positive_variables[@]}"; do
  set_numeric_defaults
  printf -v "${variable_name}" '%s' 1
  export "${variable_name}"
  assert_preflight_success "${variable_name}-one"

  set_numeric_defaults
  printf -v "${variable_name}" '%s' 0
  export "${variable_name}"
  assert_preflight_failure "${variable_name}-zero" "${variable_name}" positive 0
done

for variable_name in "${nonnegative_variables[@]}" "${positive_variables[@]}"; do
  rule=non-negative
  for positive_variable in "${positive_variables[@]}"; do
    [[ "${variable_name}" != "${positive_variable}" ]] || rule=positive
  done

  for value in "${invalid_values[@]}"; do
    set_numeric_defaults
    printf -v "${variable_name}" '%s' "${value}"
    export "${variable_name}"
    assert_preflight_failure "${variable_name}-${value// /space}" "${variable_name}" "${rule}" "${value}"
  done
done
