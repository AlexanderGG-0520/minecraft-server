#!/usr/bin/env bash
set -Eeuo pipefail

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] [$1] $2"; }
die() { log ERROR "$1"; exit 1; }

preflight() {
  log INFO "Preflight checks..."

  [[ -d /data ]] || die "/data does not exist"
  touch /data/.write_test 2>/dev/null || die "/data is not writable"
  rm -f /data/.write_test

  [[ -n "${EULA:-}" ]] || die "EULA is not set"

  case "${TYPE:-auto}" in
    auto|fabric|forge|neoforge|quilt|paper|vanilla) ;;
    *) die "Invalid TYPE: ${TYPE}" ;;
  esac

  if [[ "${TYPE:-auto}" != "auto" && -z "${VERSION:-}" ]]; then
    die "VERSION must be set when TYPE is not auto"
  fi

  rm -f /data/.ready
  log INFO "Preflight OK"
}

install_dirs() {
  log INFO "Preparing directory structure"

  mkdir -p \
    /data/logs \
    /data/mods \
    /data/config \
    /data/world

  # 権限トラブルの早期発見（非root想定なら特に重要）
  touch /data/logs/.perm_test 2>/dev/null || die "/data/logs is not writable"
  rm -f /data/logs/.perm_test

  log INFO "Directory structure ready"
}

install_eula() {
  log INFO "Handling EULA"

  case "${EULA}" in
    true)
      echo "eula=true" > /data/eula.txt
      log INFO "EULA accepted"
      ;;
    false)
      die "EULA=false. You must accept the EULA to run the server"
      ;;
    *)
      die "Invalid EULA value: ${EULA} (expected true or false)"
      ;;
  esac
}
install() {
  log INFO "Install phase start"
  install_dirs
  install_eula
  log INFO "Install phase completed (partial)"
}

runtime() {
  log INFO "Runtime phase (stub)"
  touch /data/.ready
  sleep infinity
}

main() {
  log INFO "Minecraft Runtime Booting..."
  preflight
  install
  runtime
}

main "$@"
