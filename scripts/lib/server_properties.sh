# shellcheck shell=bash

SERVER_PROPERTIES_ENV_MAP=(
  # Alias entries are listed before canonical entries. If both are exported,
  # canonical env values win because they are applied later for the same key.
  "LEVEL=level-name"
  "SEED=level-seed"
  "MODE=gamemode"
  "RESOURCE_PACK_ENFORCE=require-resource-pack"
  "RESOURCEPACK_REQUIRED=require-resource-pack"
  "RESOURCEPACK_URL=resource-pack"
  "RESOURCEPACK_SHA1=resource-pack-sha1"
  "ACCEPTS_TRANSFERS=accepts-transfers"
  "ALLOW_FLIGHT=allow-flight"
  "ALLOW_NETHER=allow-nether"
  "ANNOUNCE_PLAYER_ACHIEVEMENTS=announce-player-achievements"
  "BROADCAST_CONSOLE_TO_OPS=broadcast-console-to-ops"
  "BROADCAST_RCON_TO_OPS=broadcast-rcon-to-ops"
  "BUG_REPORT_LINK=bug-report-link"
  "DEBUG=debug"
  "DIFFICULTY=difficulty"
  "ENABLE_CODE_OF_CONDUCT=enable-code-of-conduct"
  "ENABLE_COMMAND_BLOCK=enable-command-block"
  "ENABLE_JMX_MONITORING=enable-jmx-monitoring"
  "ENABLE_QUERY=enable-query"
  "ENABLE_RCON=enable-rcon"
  "ENABLE_STATUS=enable-status"
  "ENABLE_WHITELIST=enable-whitelist"
  "ENFORCE_SECURE_PROFILE=enforce-secure-profile"
  "ENFORCE_WHITELIST=enforce-whitelist"
  "ENTITY_BROADCAST_RANGE_PERCENTAGE=entity-broadcast-range-percentage"
  "FORCE_GAMEMODE=force-gamemode"
  "FUNCTION_PERMISSION_LEVEL=function-permission-level"
  "GAMEMODE=gamemode"
  "GENERATE_STRUCTURES=generate-structures"
  "GENERATOR_SETTINGS=generator-settings"
  "HARDCORE=hardcore"
  "HIDE_ONLINE_PLAYERS=hide-online-players"
  "INITIAL_DISABLED_PACKS=initial-disabled-packs"
  "INITIAL_ENABLED_PACKS=initial-enabled-packs"
  "LEVEL_NAME=level-name"
  "LEVEL_SEED=level-seed"
  "LEVEL_TYPE=level-type"
  "LOG_IPS=log-ips"
  "MANAGEMENT_SERVER_ALLOWED_ORIGINS=management-server-allowed-origins"
  "MANAGEMENT_SERVER_ENABLED=management-server-enabled"
  "MANAGEMENT_SERVER_HOST=management-server-host"
  "MANAGEMENT_SERVER_PORT=management-server-port"
  "MANAGEMENT_SERVER_SECRET=management-server-secret"
  "MANAGEMENT_SERVER_TLS_ENABLED=management-server-tls-enabled"
  "MANAGEMENT_SERVER_TLS_KEYSTORE=management-server-tls-keystore"
  "MANAGEMENT_SERVER_TLS_KEYSTORE_PASSWORD=management-server-tls-keystore-password"
  "MAX_BUILD_HEIGHT=max-build-height"
  "MAX_COMMAND_CHAIN_LENGTH=max-command-chain-length"
  "MAX_ENTITY_CRAMMING=max-entity-cramming"
  "MAX_ENTITY_COLLISION_RADIUS=max-entity-collision-radius"
  "MAX_FUNCTION_CHAIN_DEPTH=max-function-chain-depth"
  "MAX_NEIGHBORS=max-neighbors"
  "MAX_CHAINED_NEIGHBOR_UPDATES=max-chained-neighbor-updates"
  "MAX_PLAYERS=max-players"
  "MAX_TICK_TIME=max-tick-time"
  "MAX_WORLD_SIZE=max-world-size"
  "MOTD=motd"
  "NETWORK_COMPRESSION_THRESHOLD=network-compression-threshold"
  "ONLINE_MODE=online-mode"
  "OP_PERMISSION_LEVEL=op-permission-level"
  "PAUSE_WHEN_EMPTY_SECONDS=pause-when-empty-seconds"
  "PLAYER_IDLE_TIMEOUT=player-idle-timeout"
  "PREVENT_PROXY_CONNECTIONS=prevent-proxy-connections"
  "PVP=pvp"
  "QUERY_PORT=query.port"
  "RATE_LIMIT=rate-limit"
  "RCON_PASSWORD=rcon.password"
  "RCON_PORT=rcon.port"
  "REGION_FILE_COMPRESSION=region-file-compression"
  "REQUIRE_RESOURCE_PACK=require-resource-pack"
  "RESOURCE_PACK=resource-pack"
  "RESOURCE_PACK_HASH=resource-pack-hash"
  "RESOURCE_PACK_ID=resource-pack-id"
  "RESOURCE_PACK_PROMPT=resource-pack-prompt"
  "RESOURCE_PACK_SHA1=resource-pack-sha1"
  "SERVER_IP=server-ip"
  "SERVER_NAME=server-name"
  "SERVER_PORT=server-port"
  "SIMULATION_DISTANCE=simulation-distance"
  "SNOOPER_ENABLED=snooper-enabled"
  "SPAWN_ANIMALS=spawn-animals"
  "SPAWN_MONSTERS=spawn-monsters"
  "SPAWN_NPCS=spawn-npcs"
  "SPAWN_PROTECTION=spawn-protection"
  "STATUS_HEARTBEAT_INTERVAL=status-heartbeat-interval"
  "SYNC_CHUNK_WRITES=sync-chunk-writes"
  "TEXT_FILTERING_CONFIG=text-filtering-config"
  "TEXT_FILTERING_VERSION=text-filtering-version"
  "USE_NATIVE_TRANSPORT=use-native-transport"
  "VIEW_DISTANCE=view-distance"
  "WHITE_LIST=white-list"
)

declare -A SERVER_PROPERTIES_ENV_WAS_SET=()
for server_properties_env_entry in "${SERVER_PROPERTIES_ENV_MAP[@]}"; do
  server_properties_env_key="${server_properties_env_entry%%=*}"
  if [[ "$(declare -p "$server_properties_env_key" 2>/dev/null || true)" == declare\ -x* ]]; then
    SERVER_PROPERTIES_ENV_WAS_SET["$server_properties_env_key"]=1
  fi
done
unset server_properties_env_entry server_properties_env_key

server_properties_type() {
  printf '%s' "${TYPE:-}"
}

server_properties_env_is_set() {
  local env_key="$1"
  [[ -n "${SERVER_PROPERTIES_ENV_WAS_SET[$env_key]+x}" ]]
}

normalize_env_val() {
  local value="$1"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

mask_property_log_value() {
  local key="$1"
  local value="$2"
  case "${key}" in
    rcon.password|management-server-secret|management-server-tls-keystore-password|*password*|*secret*|*token*)
      printf '%s' '<masked>'
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
}

validate_server_property_key() {
  local key="$1"
  [[ "$key" =~ ^[A-Za-z0-9_.-]+$ ]] || die "Invalid server.properties key: '${key}'"
}

validate_server_property_env_value() {
  local key="$1"
  local value="$2"

  case "$key" in
    resource-pack)
      [[ -z "$value" || "$value" == http://* || "$value" == https://* ]] \
        || die "Invalid resource-pack URL: resource-pack must be an HTTP/HTTPS URL accessible to Minecraft clients"
      ;;
  esac
}

resourcepack_public_url_auto_enabled() {
  [[ "${RESOURCEPACKS_AUTO_SET_RESOURCE_PACK:-false}" == "true" ]]
}

trim_url_boundary_slashes() {
  local value="$1"

  while [[ "$value" == */ ]]; do
    value="${value%/}"
  done
  while [[ "$value" == /* ]]; do
    value="${value#/}"
  done
  printf '%s' "$value"
}

build_resourcepack_public_url() {
  local base="${RESOURCEPACKS_PUBLIC_BASE_URL:-}"
  local prefix="${RESOURCEPACKS_S3_PREFIX:-}"
  local file="${RESOURCEPACKS_FILE:-}"
  local url

  [[ -n "$base" ]] || die "RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true but RESOURCEPACKS_PUBLIC_BASE_URL is empty"
  [[ -n "$prefix" ]] || die "RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true but RESOURCEPACKS_S3_PREFIX is empty"
  [[ -n "$file" ]] || die "RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true but RESOURCEPACKS_FILE is empty"

  while [[ "$base" == */ ]]; do
    base="${base%/}"
  done
  prefix="$(trim_url_boundary_slashes "$prefix")"
  file="$(trim_url_boundary_slashes "$file")"

  [[ -n "$base" ]] || die "RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true but RESOURCEPACKS_PUBLIC_BASE_URL is empty"
  [[ -n "$prefix" ]] || die "RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true but RESOURCEPACKS_S3_PREFIX is empty"
  [[ -n "$file" ]] || die "RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true but RESOURCEPACKS_FILE is empty"
  [[ "$base" != */"$prefix" ]] \
    || die "RESOURCEPACKS_PUBLIC_BASE_URL must be the public bucket-root URL; do not include RESOURCEPACKS_S3_PREFIX in it"

  url="${base}/${prefix}/${file}"
  validate_server_property_env_value resource-pack "$url"
  printf '%s' "$url"
}

prepare_resourcepack_public_url_env() {
  local generated_url

  if server_properties_env_is_set RESOURCE_PACK; then
    validate_server_property_env_value resource-pack "${RESOURCE_PACK}"
    return 0
  fi
  if server_properties_env_is_set RESOURCEPACK_URL; then
    validate_server_property_env_value resource-pack "${RESOURCEPACK_URL}"
    return 0
  fi

  resourcepack_public_url_auto_enabled || return 0

  generated_url="$(build_resourcepack_public_url)" || return 1
  RESOURCE_PACK="$generated_url"
  export RESOURCE_PACK
  SERVER_PROPERTIES_ENV_WAS_SET["RESOURCE_PACK"]=1
  log INFO "Generated resource-pack URL from RESOURCEPACKS_PUBLIC_BASE_URL, RESOURCEPACKS_S3_PREFIX, and RESOURCEPACKS_FILE"
}

server_property_value() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    BEGIN { prefix = key "=" }
    index($0, prefix) == 1 {
      print substr($0, length(prefix) + 1)
      exit
    }
  ' "$file"
}

server_property_exists() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    BEGIN { prefix = key "=" }
    index($0, prefix) == 1 { found = 1; exit }
    END { exit found ? 0 : 1 }
  ' "$file"
}

set_prop() {
  local key="$1"
  local value="$2"
  local file="${3:-${SERVER_PROPERTIES:-${DATA_DIR}/server.properties}}"
  local tmp

  validate_server_property_key "$key"

  tmp="$(mktemp "${file}.tmp.XXXXXX")" || die "Failed to create temp file for ${file}"
  if [[ ! -f "$file" ]]; then
    if ! printf '%s=%s\n' "$key" "$value" > "$tmp"; then
      rm -f "$tmp"
      die "Failed to update server.properties file '${file}'"
    fi
    if ! mv "$tmp" "$file"; then
      rm -f "$tmp"
      die "Failed to replace server.properties file '${file}'"
    fi
    return 0
  fi

  if ! awk -v key="$key" -v value="$value" '
      BEGIN {
        prefix = key "="
        found = 0
      }
      index($0, prefix) == 1 {
        if (!found) {
          print prefix value
          found = 1
        }
        next
      }
      { print }
      END {
        if (!found) {
          print prefix value
        }
      }
    ' "$file" > "$tmp"; then
    rm -f "$tmp"
    die "Failed to update server.properties file '${file}'"
  fi

  if ! mv "$tmp" "$file"; then
    rm -f "$tmp"
    die "Failed to replace server.properties file '${file}'"
  fi
}

apply_server_properties_diff() {
  local props_file="${DATA_DIR}/server.properties"
  local entry env_key prop_key env_val current_val log_val action

  if [[ ! -f "$props_file" ]]; then
    log INFO "server.properties not found, skipping diff apply"
    return 0
  fi

  if [[ "${APPLY_SERVER_PROPERTIES_DIFF:-true}" != "true" ]]; then
    log INFO "APPLY_SERVER_PROPERTIES_DIFF=false, skipping"
    return 0
  fi

  log INFO "Applying server.properties diff (runtime-only)"

  for entry in "${SERVER_PROPERTIES_ENV_MAP[@]}"; do
    env_key="${entry%%=*}"
    prop_key="${entry#*=}"

    if ! server_properties_env_is_set "$env_key"; then
      continue
    fi

    env_val="$(normalize_env_val "${!env_key}")"
    validate_server_property_env_value "$prop_key" "$env_val"
    current_val="$(server_property_value "$props_file" "$prop_key")"
    if server_property_exists "$props_file" "$prop_key"; then
      action="Updated"
      [[ "$current_val" == "$env_val" ]] && continue
    else
      action="Added"
    fi

    set_prop "$prop_key" "$env_val" "$props_file"
    log_val="$(mask_property_log_value "$prop_key" "$env_val")"
    log INFO "${action} property: ${prop_key}=${log_val}"
  done

  log INFO "server.properties diff apply completed"
}

apply_rcon_settings() {
  if [[ "${ENABLE_RCON:-false}" == "true" ]]; then
    set_prop enable-rcon true
    set_prop rcon.port "${RCON_PORT:-25575}"

    [[ -n "${RCON_PASSWORD:-}" ]] || die "ENABLE_RCON=true but RCON_PASSWORD is empty"
    [[ "${RCON_PASSWORD}" != "changeme" ]] || die "RCON_PASSWORD=changeme is not allowed"

    set_prop rcon.password "${RCON_PASSWORD}"
  else
    set_prop enable-rcon false
  fi
}

install_server_properties() {
  # shellcheck disable=SC2034  # Retained as a conventional path binding for this install step.
  PROPS_FILE="${DATA_DIR}/server.properties"

  ensure_server_properties

  if [[ "${APPLY_SERVER_PROPERTIES_DIFF:-true}" == "true" ]]; then
    log INFO "server.properties ready, applying env diff"
    prepare_resourcepack_public_url_env
    apply_server_properties_diff
  else
    log INFO "server.properties exists, no changes applied"
  fi

  apply_rcon_settings
}

ensure_server_properties() {
  local props="${DATA_DIR}/server.properties"
  local type
  type="$(server_properties_type)"

  if ! uses_server_properties "$type"; then
    log INFO "TYPE=${type} does not use server.properties, skipping bootstrap"
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
  local bootstrap_timeout
  local props="${DATA_DIR}/server.properties"
  local type
  type="$(server_properties_type)"

  if [[ -f "$props" ]]; then
    log INFO "server.properties already exists"
    return 0
  fi

  log INFO "server.properties not found, bootstrapping via official server"

  case "$type" in
    forge|neoforge)
      bootstrap_timeout="${SERVER_PROPERTIES_BOOTSTRAP_TIMEOUT:-90s}"
      ;;
    *)
      bootstrap_timeout="${SERVER_PROPERTIES_BOOTSTRAP_TIMEOUT:-15s}"
      ;;
  esac

  log INFO "server.properties bootstrap timeout: ${bootstrap_timeout}"

  case "$type" in
    vanilla|paper|purpur|spigot)
      timeout "${bootstrap_timeout}" java -jar "${DATA_DIR}/server.jar" nogui || true
      ;;
    fabric)
      timeout "${bootstrap_timeout}" java -jar "${DATA_DIR}/fabric-server-launch.jar" nogui || true
      ;;
    forge|neoforge)
      # NeoForge / Forge must go through run.sh
      if [[ -x "${DATA_DIR}/run.sh" ]]; then
        timeout "${bootstrap_timeout}" "${DATA_DIR}/run.sh" nogui || true
      else
        log WARN "run.sh not found, cannot bootstrap properties yet"
        return 1
      fi
      ;;
    *)
      die "bootstrap_server_properties: unsupported TYPE=${type}"
      ;;
  esac

  if [[ ! -f "$props" ]]; then
    die "server.properties still not generated after bootstrap (TYPE=${type}, timeout=${bootstrap_timeout})"
  fi

  log INFO "server.properties successfully bootstrapped"
}
