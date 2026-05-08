# shellcheck shell=bash

: "${LOG_TZ:=UTC}"
: "${LOG_TS_FORMAT:=iso8601}"

ts() {
  if [[ "${LOG_TS_FORMAT}" == "iso8601" ]]; then
    TZ="${LOG_TZ}" date +"%Y-%m-%dT%H:%M:%S%:z"
  else
    TZ="${LOG_TZ}" date +"${LOG_TS_FORMAT}"
  fi
}

log() {
  local level="$1"; shift || true
  # Use printf with %s to avoid format string injection; join remaining args as message
  printf '[%s] [%s] %s\n' "$(ts)" "$level" "$*" >&2
}

die() { log ERROR "$1"; exit 1; }
