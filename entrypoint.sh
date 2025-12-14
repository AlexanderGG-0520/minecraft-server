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
install_server() {
  log INFO "Resolving server (TYPE=${TYPE}, VERSION=${VERSION:-auto})"

  case "${TYPE}" in
    auto)
      if [[ ! -f /data/server.jar ]]; then
        log INFO "Creating dummy server.jar (auto mode)"
        echo "dummy server jar" > /data/server.jar
      else
        log INFO "server.jar already exists, skipping"
      fi
      ;;

    vanilla)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for vanilla"

      if [[ -f /data/server.jar ]]; then
        log INFO "server.jar already exists, skipping"
        return
      fi

      log INFO "Downloading vanilla server ${VERSION}"

      meta_url="$(curl -fsSL https://launchermeta.mojang.com/mc/game/version_manifest.json \
        | jq -r '.versions[] | select(.id=="'"${VERSION}"'") | .url')"
      [[ -n "${meta_url}" && "${meta_url}" != "null" ]] || die "Invalid VERSION: ${VERSION}"

      sha1="$(curl -fsSL "${meta_url}" | jq -r '.downloads.server.sha1')"
      [[ -n "${sha1}" && "${sha1}" != "null" ]] || die "Failed to resolve server sha1"

      curl -fL "https://piston-data.mojang.com/v1/objects/${sha1}/server.jar" \
        -o /data/server.jar \
        || die "Failed to download vanilla server.jar"

      log INFO "Vanilla server.jar downloaded"
      ;;

    *)
      die "install_server: TYPE=${TYPE} not implemented yet"
      ;;
  esac
}

install() {
  log INFO "Install phase start"
  install_dirs
  install_eula
  install_server
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
