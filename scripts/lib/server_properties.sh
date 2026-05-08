# shellcheck shell=bash

ensure_server_properties() {
  local props="${DATA_DIR}/server.properties"

  if ! uses_server_properties "${TYPE:-}"; then
    log INFO "TYPE=${TYPE:-} does not use server.properties, skipping bootstrap"
    return 0
  fi

  if [[ ! -f "$props" ]]; then
    log INFO "server.properties not found, generating via bootstrap"
    bootstrap_server_properties
  else
    log INFO "server.properties already exists"
  fi
}

bootstrap_server_properties() {
  local props="${DATA_DIR}/server.properties"

  if [[ -f "$props" ]]; then
    log INFO "server.properties already exists"
    return 0
  fi

  log INFO "server.properties not found, bootstrapping via official server"

  case "${TYPE}" in
    vanilla|paper|purpur|spigot)
      timeout 15s java -jar "${DATA_DIR}/server.jar" nogui || true
      ;;
    fabric)
      timeout 15s java -jar "${DATA_DIR}/fabric-server-launch.jar" nogui || true
      ;;
    forge|neoforge)
      # NeoForge / Forge must go through run.sh
      if [[ -x "${DATA_DIR}/run.sh" ]]; then
        timeout 15s "${DATA_DIR}/run.sh" nogui || true
      else
        log WARN "run.sh not found, cannot bootstrap properties yet"
        return 1
      fi
      ;;
    *)
      die "bootstrap_server_properties: unsupported TYPE=${TYPE}"
      ;;
  esac

  if [[ ! -f "$props" ]]; then
    die "server.properties still not generated after bootstrap"
  fi

  log INFO "server.properties successfully bootstrapped"
}
