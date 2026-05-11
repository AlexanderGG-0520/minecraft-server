# shellcheck shell=bash

rcon_client() {
  if command -v rcon-cli >/dev/null 2>&1; then
    echo "rcon-cli"
    return 0
  fi
  if command -v mcrcon >/dev/null 2>&1; then
    echo "mcrcon"
    return 0
  fi
  return 1
}

rcon_exec() {
  local command="$*"
  local attempt=1

  if [[ "${ENABLE_RCON}" != "true" ]]; then
    log INFO "RCON disabled, skipping command: ${command}"
    return 1
  fi

  if [[ -z "${RCON_PASSWORD:-}" ]]; then
    log ERROR "RCON_PASSWORD is empty, cannot execute: ${command}"
    return 1
  fi

  local client
  if ! client="$(rcon_client)"; then
    log ERROR "No RCON client found (rcon-cli or mcrcon), cannot execute: ${command}"
    return 1
  fi

  while true; do
    if [[ "${client}" == "rcon-cli" ]]; then
      if timeout "${RCON_TIMEOUT}" \
        rcon-cli --host "${RCON_HOST}" --port "${RCON_PORT}" --password "${RCON_PASSWORD}" "${command}"; then
        return 0
      fi
    else
      if timeout "${RCON_TIMEOUT}" \
        mcrcon -H "${RCON_HOST}" -P "${RCON_PORT}" -p "${RCON_PASSWORD}" "${command}"; then
        return 0
      fi
    fi

    if (( attempt >= RCON_RETRIES )); then
      log ERROR "RCON command failed after ${attempt} attempts: ${command}"
      return 1
    fi

    log WARN "RCON command failed (attempt ${attempt}/${RCON_RETRIES}), retrying: ${command}"
    attempt=$((attempt + 1))
    sleep "${RCON_RETRY_DELAY}"
  done
}

rcon_say() {
  rcon_exec "say $*"
}

rcon_tellraw_all() {
  local message="$*"
  local shown
  shown="$(json_escape "$message")"

  # tellraw first; if it fails, fallback to say
  if ! rcon_exec "tellraw @a {\"text\":\"${shown}\",\"color\":\"yellow\"}"; then
    log WARN "tellraw failed; falling back to say"
    rcon_exec "say ${message}" || true
    return 1
  fi
  return 0
}
