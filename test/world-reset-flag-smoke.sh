#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh
source ./scripts/lib/world_reset.sh

flag_removals_file="$tmp/flag-removals"
: > "$flag_removals_file"

safe_rm_f() {
  local path="${1:-}"

  if [[ -n "${DATA_DIR:-}" && "${path}" == "${DATA_DIR}/reset-world.flag" ]]; then
    printf '%s\n' "$path" >> "$flag_removals_file"
  fi

  command rm -f -- "$path"
}

reset_flag_removal_count() {
  : > "$flag_removals_file"
}

flag_removal_count() {
  wc -l < "$flag_removals_file"
}

assert_file_absent() {
  local path="$1"

  if [[ -e "$path" ]]; then
    echo "FAIL: expected ${path} to be absent" >&2
    exit 1
  fi
}

assert_file_present() {
  local path="$1"

  if [[ ! -e "$path" ]]; then
    echo "FAIL: expected ${path} to exist" >&2
    exit 1
  fi
}

assert_flag_removals() {
  local expected="$1"
  local actual

  actual="$(flag_removal_count)"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: expected ${expected} reset flag removals, got ${actual}" >&2
    exit 1
  fi
}

expect_failure() {
  local name="$1"
  shift

  set +e
  "$@" >/dev/null 2>&1
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "FAIL: expected failure for ${name}" >&2
    exit 1
  fi
}

run_successful_reset_consumes_flag_once() {
  DATA_DIR="$tmp/success"
  RESET_WORLD_BACKUP=false
  RESET_WORLD_REMOVE_MODS=false
  mkdir -p "$DATA_DIR/world"
  printf '%s\n' world > "$DATA_DIR/world/level.dat"
  touch "$DATA_DIR/.ready" "$DATA_DIR/reset-world.flag"

  reset_flag_removal_count
  output="$(handle_reset_world_flag 2>&1)"

  assert_file_absent "$DATA_DIR/reset-world.flag"
  assert_file_absent "$DATA_DIR/.ready"
  assert_file_absent "$DATA_DIR/world/level.dat"
  assert_file_present "$DATA_DIR/world"
  assert_flag_removals 1

  if [[ "$(printf '%s\n' "$output" | grep -c 'reset-world.flag consumed')" != "1" ]]; then
    echo "FAIL: expected one consumed log line" >&2
    exit 1
  fi
}

run_direct_reset_world_consumes_flag_once() {
  DATA_DIR="$tmp/direct"
  RESET_WORLD_BACKUP=false
  RESET_WORLD_REMOVE_MODS=false
  mkdir -p "$DATA_DIR/world"
  printf '%s\n' world > "$DATA_DIR/world/level.dat"
  touch "$DATA_DIR/reset-world.flag"

  reset_flag_removal_count
  output="$(reset_world 2>&1)"

  assert_file_absent "$DATA_DIR/reset-world.flag"
  assert_file_absent "$DATA_DIR/world/level.dat"
  assert_file_present "$DATA_DIR/world"
  assert_flag_removals 1

  if ! printf '%s\n' "$output" | grep -q 'World reset completed successfully'; then
    echo "FAIL: expected direct reset success log line" >&2
    exit 1
  fi
}

run_absent_flag_skips_reset() {
  DATA_DIR="$tmp/absent"
  RESET_WORLD_BACKUP=false
  RESET_WORLD_REMOVE_MODS=false
  mkdir -p "$DATA_DIR/world"
  printf '%s\n' world > "$DATA_DIR/world/level.dat"

  reset_flag_removal_count
  output="$(handle_reset_world_flag 2>&1)"

  assert_file_present "$DATA_DIR/world/level.dat"
  assert_flag_removals 0

  if ! printf '%s\n' "$output" | grep -q 'No reset-world.flag detected, skipping world reset'; then
    echo "FAIL: expected no-reset log line" >&2
    exit 1
  fi
}

run_missing_world_consumes_flag_once() {
  DATA_DIR="$tmp/missing-world"
  RESET_WORLD_BACKUP=false
  RESET_WORLD_REMOVE_MODS=false
  mkdir -p "$DATA_DIR"
  touch "$DATA_DIR/reset-world.flag"

  reset_flag_removal_count
  output="$(handle_reset_world_flag 2>&1)"

  assert_file_absent "$DATA_DIR/reset-world.flag"
  assert_flag_removals 1

  if ! printf '%s\n' "$output" | grep -q 'World directory does not exist, nothing to reset'; then
    echo "FAIL: expected missing-world log line" >&2
    exit 1
  fi
}

run_expired_flag_is_removed_once() {
  DATA_DIR="$tmp/expired"
  RESET_WORLD_BACKUP=false
  RESET_WORLD_REMOVE_MODS=false
  mkdir -p "$DATA_DIR/world"
  touch -d '1 hour ago' "$DATA_DIR/reset-world.flag"

  reset_flag_removal_count
  output="$(handle_reset_world_flag 2>&1)"

  assert_file_absent "$DATA_DIR/reset-world.flag"
  assert_file_present "$DATA_DIR/world"
  assert_flag_removals 1

  if ! printf '%s\n' "$output" | grep -q 'reset-world.flag expired'; then
    echo "FAIL: expected expired-flag log line" >&2
    exit 1
  fi
}

run_unsafe_reset_paths_are_rejected() {
  expect_failure \
    "empty DATA_DIR reset paths" \
    validate_world_reset_paths "" "/world" "/reset-world.flag" "/backups" "" "" false false

  expect_failure \
    "root DATA_DIR reset paths" \
    validate_world_reset_paths "/" "/world" "/reset-world.flag" "/backups" "" "" false false

  local data_root="$tmp/data-root"
  mkdir -p "$data_root"
  expect_failure \
    "WORLD_DIR equals DATA_DIR" \
    validate_world_reset_paths \
      "$data_root" \
      "$data_root" \
      "$data_root/reset-world.flag" \
      "$data_root/backups" \
      "" \
      "$data_root/mods" \
      false \
      false
}

run_relative_data_dir_reset_is_rejected() {
  local case_dir="$tmp/relative-case"
  mkdir -p "$case_dir/relative-data/world"
  printf '%s\n' world > "$case_dir/relative-data/world/level.dat"
  touch "$case_dir/relative-data/reset-world.flag"

  reset_flag_removal_count
  set +e
  output="$(
    cd "$case_dir"
    DATA_DIR="relative-data"
    RESET_WORLD_BACKUP=false
    RESET_WORLD_REMOVE_MODS=false
    reset_world 2>&1
  )"
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "FAIL: expected relative DATA_DIR reset to fail" >&2
    exit 1
  fi

  assert_file_present "$case_dir/relative-data/reset-world.flag"
  assert_file_present "$case_dir/relative-data/world/level.dat"
  assert_flag_removals 0

  if ! printf '%s\n' "$output" | grep -q 'Refusing unsafe world reset path'; then
    echo "FAIL: expected unsafe reset path log line" >&2
    exit 1
  fi
}

run_successful_reset_consumes_flag_once
run_direct_reset_world_consumes_flag_once
run_absent_flag_skips_reset
run_missing_world_consumes_flag_once
run_expired_flag_is_removed_once
run_unsafe_reset_paths_are_rejected
run_relative_data_dir_reset_is_rejected
