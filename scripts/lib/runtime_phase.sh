# shellcheck shell=bash

run_runtime_phase() {
  install

  if is_true "${INSTALL_ONLY:-false}"; then
    log WARN "INSTALL_ONLY=true, skipping runtime launch and exiting"
    exit 0
  fi

  runtime
}
