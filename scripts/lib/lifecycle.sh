# shellcheck shell=bash

run_phase_hooks() {
  local phase="$1"
  local dir="${HOOKS_DIR}/${phase}.d"
  local ran=0
  local hook
  local rc

  is_true "${HOOKS_ENABLED:-false}" || return 0

  if [[ ! -d "${dir}" ]]; then
    log INFO "Hooks enabled but '${dir}' not found, skipping ${phase} hooks"
    return 0
  fi

  shopt -s nullglob
  for hook in "${dir}"/*; do
    [[ -f "${hook}" ]] || continue
    [[ -x "${hook}" ]] || {
      log WARN "Skipping non-executable hook: ${hook}"
      continue
    }

    ran=1
    log INFO "Running ${phase} hook: ${hook}"
    if [[ "${HOOKS_TIMEOUT_SEC:-0}" =~ ^[0-9]+$ ]] && (( HOOKS_TIMEOUT_SEC > 0 )); then
      timeout "${HOOKS_TIMEOUT_SEC}s" env HOOK_PHASE="${phase}" "${hook}" || rc=$?
    else
      HOOK_PHASE="${phase}" "${hook}" || rc=$?
    fi

    if [[ "${rc:-0}" -ne 0 ]]; then
      if [[ "${rc}" -eq 124 ]]; then
        log WARN "${phase} hook timed out after ${HOOKS_TIMEOUT_SEC}s: ${hook}"
      fi
      if is_true "${HOOKS_STRICT:-true}"; then
        die "${phase} hook failed (rc=${rc}): ${hook}"
      fi
      log WARN "${phase} hook failed but continuing (HOOKS_STRICT=false, rc=${rc}): ${hook}"
    fi
    rc=0
  done
  shopt -u nullglob

  [[ "${ran}" -eq 1 ]] || log INFO "No executable hooks found in ${dir}"
}
