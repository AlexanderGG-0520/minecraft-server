#!/usr/bin/env bash
set -Eeuo pipefail

ENTRYPOINT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/lib/logging.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/logging.sh"
# shellcheck source=scripts/lib/filesystem.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/filesystem.sh"
# shellcheck source=scripts/lib/runtime.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/runtime.sh"
# shellcheck source=scripts/lib/preflight.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/preflight.sh"
# shellcheck source=scripts/lib/runtime_env.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/runtime_env.sh"
# shellcheck source=scripts/lib/c2me.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/c2me.sh"
# shellcheck source=scripts/lib/jvm_args.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/jvm_args.sh"
# shellcheck source=scripts/lib/player_lists.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/player_lists.sh"
# shellcheck source=scripts/lib/paper_config.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/paper_config.sh"
# shellcheck source=scripts/lib/bootstrap_files.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/bootstrap_files.sh"
# shellcheck source=scripts/lib/lifecycle.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/lifecycle.sh"
# shellcheck source=scripts/lib/rcon.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/rcon.sh"
# shellcheck source=scripts/lib/shutdown.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/shutdown.sh"
# shellcheck source=scripts/lib/s3_client.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/s3_client.sh"
# shellcheck source=scripts/lib/content_assets.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/content_assets.sh"
# shellcheck source=scripts/lib/mods.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/mods.sh"
# shellcheck source=scripts/lib/velocity_config.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/velocity_config.sh"
# shellcheck source=scripts/lib/server_install.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/server_install.sh"
# shellcheck source=scripts/lib/runtime_launch.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/runtime_launch.sh"
# shellcheck source=scripts/lib/world_install.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/world_install.sh"
# shellcheck source=scripts/lib/world_reset.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/world_reset.sh"
# shellcheck source=scripts/lib/server_properties.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/server_properties.sh"
# shellcheck source=scripts/lib/install_phase.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/install_phase.sh"
# shellcheck source=scripts/lib/command_mode.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/command_mode.sh"
# shellcheck source=scripts/lib/runtime_phase.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/runtime_phase.sh"

# shellcheck disable=SC2034  # Reserved global for PID-oriented lifecycle handling.
MC_PID=""

# ================================
# Force IPv4 (IMPORTANT)
# ================================
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} \
-Djava.net.preferIPv4Stack=true \
-Djava.net.preferIPv4Addresses=true \
-Duser.timezone=${LOG_TZ}"

log INFO "JAVA_TOOL_OPTIONS=${JAVA_TOOL_OPTIONS}"

# ============================================================
# Environment defaults (non server.properties)
# ============================================================

# Java
: "${JAVA_MAJOR:=unknown}"
: "${JAVA_VERSION_RAW:=unknown}"
: "${JAVA_VENDOR:=unknown}"

: "${RUNTIME_ARCH_NORM:=unknown}"
: "${RUNTIME_CONTAINER:=unknown}"
: "${RUNTIME_GPU:=none}"

# Global Paths
: "${DATA_DIR:=/data}"
: "${JVM_ARGS_FILE:=${DATA_DIR}/jvm.args}"

# UID/GID
: "${UID:=1000}"
: "${GID:=1000}"

# Runtime
: "${TYPE:=vanilla}"
: "${READY_DELAY:=5}"
: "${HOOKS_ENABLED:=false}"
: "${HOOKS_DIR:=/hooks}"
: "${HOOKS_STRICT:=true}"
: "${HOOKS_TIMEOUT_SEC:=0}"
: "${INSTALL_ONLY:=false}"

# JVM
: "${JVM_XMS:=512M}"
: "${JVM_XMX:=512M}"
: "${JVM_GC:=G1}"
: "${JVM_USE_CONTAINER_SUPPORT:=true}"
: "${JVM_EXTRA_ARGS:=}"

# Mods
: "${MODS_ENABLED:=true}"
: "${MODS_S3_PREFIX:=mods/latest}"
: "${MODS_SYNC_ONCE:=true}"
: "${MODS_REMOVE_EXTRA:=false}"

# Plugins
: "${PLUGINS_ENABLED:=true}"
: "${PLUGINS_S3_PREFIX:=plugins/latest}"
: "${PLUGINS_SYNC_ONCE:=true}"
: "${PLUGINS_REMOVE_EXTRA:=false}"

# Configs
: "${CONFIGS_ENABLED:=true}"
: "${CONFIGS_S3_PREFIX:=configs/latest}"
: "${CONFIGS_SYNC_ONCE:=true}"
: "${CONFIGS_REMOVE_EXTRA:=false}"

# Datapacks
: "${DATAPACKS_ENABLED:=true}"
: "${DATAPACKS_S3_PREFIX:=datapacks/latest}"
: "${DATAPACKS_SYNC_ONCE:=true}"
: "${DATAPACKS_REMOVE_EXTRA:=false}"

# Resourcepacks
: "${RESOURCEPACKS_ENABLED:=true}"
: "${RESOURCEPACKS_S3_PREFIX:=resourcepacks/latest}"
: "${RESOURCEPACKS_SYNC_ONCE:=true}"
: "${RESOURCEPACKS_REMOVE_EXTRA:=false}"
: "${RESOURCEPACKS_AUTO_APPLY:=true}"
: "${RESOURCEPACK_REQUIRED:=false}"

# Modpacks (experimental)
: "${MODPACK_URL:=}"
: "${MODPACK_FORMAT:=auto}"
: "${MODPACK_INSTALL_MODE:=server}"
: "${MODPACK_FORCE_REINSTALL:=false}"
: "${MODPACK_REMOVE_EXTRA:=false}"
: "${MODPACK_INCLUDE_OPTIONAL:=false}"
: "${MODPACK_ALLOW_FILE_URL:=false}"

# F-3: C2ME (EXPERIMENTAL)
: "${ENABLE_C2ME:=false}"
: "${ENABLE_C2ME_HARDWARE_ACCELERATION:=false}"
: "${I_KNOW_C2ME_IS_EXPERIMENTAL:=false}"

# RCON
: "${ENABLE_RCON:=false}"
: "${RCON_HOST:=127.0.0.1}"
: "${RCON_PORT:=25575}"
: "${RCON_PASSWORD:=}"


# ============================================================
# Input directories (external / immutable)
# ============================================================
: "${INPUT_MODS_DIR:=/mods}"
: "${INPUT_PLUGINS_DIR:=/plugins}"
: "${INPUT_CONFIG_DIR:=/config}"
: "${INPUT_DATAPACKS_DIR:=/datapacks}"
: "${INPUT_RESOURCEPACKS_DIR:=/resourcepacks}"
: "${MC_CONFIG_DIR:=/tmp/mc-config}"
export MC_CONFIG_DIR
# ============================================================

# RCON (runtime control)
: "${STOP_SERVER_ANNOUNCE_DELAY:=0}"
# ============================================================
# Server Icon
: "${SERVER_ICON_URL:=}"
# ============================================================

clear_fabric_cache() {
# -----------------------------
# Clean Fabric mapping cache
# -----------------------------
case "${TYPE}" in
  fabric|taiyitist|quilt)
    log INFO "Cleaning Fabric mapping/cache directories (TYPE=${TYPE})"
    safe_rm_rf "${DATA_DIR}/.fabric"
    safe_rm_rf "${DATA_DIR}/.cache"
    safe_rm_rf "${DATA_DIR}/.mappings"
    log INFO "Fabric mapping/cache directories cleaned"
    ;;
esac
}

normalize_toml_key() {
  printf '%s\n' "${1//[^a-zA-Z0-9_]/_}"
}

declare -A VELOCITY_SERVER_KEYS

IFS=',' read -ra ENTRIES <<< "${VELOCITY_SERVERS:-}"
for entry in "${ENTRIES[@]}"; do
  raw_key="${entry%%=*}"
  key="$(normalize_toml_key "${raw_key}")"
  VELOCITY_SERVER_KEYS["${key}"]=1
done

is_true() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

# Add to appropriate location if missing (bash assumed)
trim_ws() {
  local s="$1"
  # leading
  s="${s#"${s%%[![:space:]]*}"}"
  # trailing
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# ===========================================
# server.properties env -> key mapping
# ===========================================
declare -A PROP_MAP=(
  # --- General ---
  [MOTD]="motd"
  [DIFFICULTY]="difficulty"
  [GAMEMODE]="gamemode"
  [HARDCORE]="hardcore"
  [FORCE_GAMEMODE]="force-gamemode"
  [ALLOW_FLIGHT]="allow-flight"
  [SPAWN_PROTECTION]="spawn-protection"
  [MAX_PLAYERS]="max-players"
  [VIEW_DISTANCE]="view-distance"
  [SIMULATION_DISTANCE]="simulation-distance"
  [PVP]="pvp"

  # --- Phase A: Management / Behavior ---
  [ENABLE_WHITELIST]="enable-whitelist"
  [WHITE_LIST]="white-list"
  [ENFORCE_WHITELIST]="enforce-whitelist"
  [OP_PERMISSION_LEVEL]="op-permission-level"
  [FUNCTION_PERMISSION_LEVEL]="function-permission-level"
  [LOG_IPS]="log-ips"
  [BROADCAST_CONSOLE_TO_OPS]="broadcast-console-to-ops"
  [BROADCAST_RCON_TO_OPS]="broadcast-rcon-to-ops"

  # --- Phase B: Performance / Stability ---
  [MAX_TICK_TIME]="max-tick-time"
  [SYNC_CHUNK_WRITES]="sync-chunk-writes"
  [ENTITY_BROADCAST_RANGE_PERCENTAGE]="entity-broadcast-range-percentage"
  [MAX_CHAINED_NEIGHBOR_UPDATES]="max-chained-neighbor-updates"

  # --- Phase C: Query / RCON / External Integration ---
  [ENABLE_QUERY]="enable-query"
  [QUERY_PORT]="query.port"
  [ENABLE_RCON]="enable-rcon"
  [RCON_PORT]="rcon.port"
  [RCON_PASSWORD]="rcon.password"
  [RESOURCE_PACK]="resource-pack"
  [RESOURCE_PACK_SHA1]="resource-pack-sha1"
  [REQUIRE_RESOURCE_PACK]="require-resource-pack"

  # --- Phase D: Worldgen ---
  [LEVEL]="level-name"
  [LEVEL_SEED]="level-seed"
  [LEVEL_TYPE]="level-type"
  [GENERATE_STRUCTURES]="generate-structures"
  [GENERATOR_SETTINGS]="generator-settings"

  # --- Phase E: Networking / Connections ---
  [ENFORCE_SECURE_PROFILE]="enforce-secure-profile"
  [NETWORK_COMPRESSION_THRESHOLD]="network-compression-threshold"
  [MAX_WORLD_SIZE]="max-world-size"
  [MAX_BUILD_HEIGHT]="max-build-height"
  [ONLINE_MODE]="online-mode"
  [SERVER_PORT]="server-port"
  [SERVER_IP]="server-ip"
)

# Escape string for safe sed usage
# Convert actual newlines to \n string
normalize_env_val() {
  printf '%s' "$1" | sed ':a;N;$!ba;s/\n/\\n/g'
}

escape_sed_replacement() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//&/\\&}"
  s="${s//|/\\|}"
  printf '%s' "$s"
}

mask_property_log_value() {
  local key="$1"
  local value="$2"
  case "${key}" in
    rcon.password|*secret*|*password*|*token*|*key*)
      printf '%s' '<masked>'
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
}

apply_server_properties_diff() {
  local props_file="${DATA_DIR}/server.properties"

  # ------------------------------------------------------------
  # Guard
  # ------------------------------------------------------------
  if [[ ! -f "$props_file" ]]; then
    log INFO "server.properties not found, skipping diff apply"
    return 0
  fi

  if [[ "${APPLY_SERVER_PROPERTIES_DIFF:-true}" != "true" ]]; then
    log INFO "APPLY_SERVER_PROPERTIES_DIFF=false, skipping"
    return 0
  fi

  log INFO "Applying server.properties diff (runtime-only)"

  # ------------------------------------------------------------
  # Apply ENV-based overrides
  # ------------------------------------------------------------
  for ENV_KEY in "${!PROP_MAP[@]}"; do
    local PROP_KEY="${PROP_MAP[$ENV_KEY]}"
    local ENV_VAL

    # set -u safe
    ENV_VAL="${!ENV_KEY:-}"
    ENV_VAL="$(normalize_env_val "$ENV_VAL")"

    # Skip unset / empty envs
    [[ -z "$ENV_VAL" ]] && continue

    # Read current value (may be empty)
    local CURRENT_VAL
    CURRENT_VAL="$(grep -E "^${PROP_KEY}=" "$props_file" | cut -d= -f2- || true)"

    # No change needed
    if [[ "$CURRENT_VAL" == "$ENV_VAL" ]]; then
      continue
    fi

    # Update or append
    local LOG_VAL
    LOG_VAL="$(mask_property_log_value "$PROP_KEY" "$ENV_VAL")"
    if grep -qE "^${PROP_KEY}=" "$props_file"; then
      local SED_VAL
      SED_VAL="$(escape_sed_replacement "$ENV_VAL")"
      sed -i "s|^${PROP_KEY}=.*|${PROP_KEY}=${SED_VAL}|" "$props_file"
      log INFO "Updated property: ${PROP_KEY}=${LOG_VAL}"
    else
      echo "${PROP_KEY}=${ENV_VAL}" >> "$props_file"
      log INFO "Added property: ${PROP_KEY}=${LOG_VAL}"
    fi
  done

  log INFO "server.properties diff apply completed"
}

set_prop() {
  local key="$1"
  local value="$2"
  local file="${SERVER_PROPERTIES:-${DATA_DIR}/server.properties}"

  # Replace if key exists, append if not
  if grep -qE "^${key}=" "$file"; then
    local sed_value
    sed_value="$(escape_sed_replacement "$value")"
    sed -i "s|^${key}=.*|${key}=${sed_value}|" "$file"
  else
    echo "${key}=${value}" >> "$file"
  fi
}

apply_rcon_settings() {
  if [[ "${ENABLE_RCON}" == "true" ]]; then
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
    apply_server_properties_diff
  else
    log INFO "server.properties exists, no changes applied"
  fi

  apply_rcon_settings
}

# shellcheck disable=SC2034  # Reserved managed-path anchor for optimize-mods handling.
OPT_MANAGED_DIR="${DATA_DIR}/.managed/optimize-mods"
OPT_LINK_PREFIX="zz-opt-"

opt_bool() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

opt_type_family() {
  # TYPE is assumed already set (fabric|quilt|forge|neoforge|...)
  case "${TYPE:-}" in
    fabric|quilt) echo "fabric" ;;
    forge|neoforge) echo "forge" ;;
    *) echo "unknown" ;;
  esac
}

opt_required_any_enabled() {
  local fam="$1"
  if [[ "$fam" == "fabric" ]]; then
    opt_bool "$OPTIMIZE_LITHIUM" && return 0
    opt_bool "$OPTIMIZE_FERRITECORE" && return 0
    return 1
  elif [[ "$fam" == "forge" ]]; then
    opt_bool "$OPTIMIZE_FERRITECORE" && return 0
    opt_bool "$OPTIMIZE_MODERNFIX" && return 0
    return 1
  fi
  return 1
}

opt_mc_configure_alias() {
  configure_mc_alias "optimize mods"
}

opt_mirror_from_s3() {
  local src="$1"  # like: s3/bucket/prefix/type
  local dst="$2"

  mkdir -p "$dst"

  # IMPORTANT: no --remove here (rule!)
  # We allow overwrite so updates propagate.
  mc mirror --overwrite "$src" "$dst"
}

opt_install_links() {
  local cache_dir="$1"
  local mods_dir="$2"

  mkdir -p "$mods_dir"

  # Remove stale symlinks we previously created (safe: only symlink + prefix)
  find "$mods_dir" -maxdepth 1 -type l -name "${OPT_LINK_PREFIX}*.jar" -print0 2>/dev/null \
    | while IFS= read -r -d '' link; do
        local target
        target="$(readlink "$link" || true)"
        if [[ -z "$target" || ! -e "$mods_dir/$target" && ! -e "$target" ]]; then
          safe_rm_f "$link"
        fi
      done

  # Create/refresh symlinks for jars in cache
  local found=0
  shopt -s nullglob
  for jar in "$cache_dir"/*.jar; do
    found=1
    local base
    base="$(basename "$jar")"
    local link="${mods_dir}/${OPT_LINK_PREFIX}${base}"

    # If a non-symlink file exists with same name, don't touch it.
    if [[ -e "$link" && ! -L "$link" ]]; then
      log WARN "Optimize link name conflict (not a symlink), skipping: $link"
      continue
    fi

    ln -sf "$jar" "$link"
  done
  shopt -u nullglob

  [[ $found -eq 1 ]] && return 0 || return 1
}

is_world_generated() {
  [[ -f "${DATA_DIR}/world/level.dat" ]]
}

wait_for_worldgen() {
  log INFO "Waiting for world generation to complete"
  while ! is_world_generated; do
    sleep 1
  done
  log INFO "World generation confirmed (level.dat found)"
}

: "${RCON_RETRIES:=5}"
: "${RCON_RETRY_DELAY:=1}"
: "${RCON_TIMEOUT:=5}"
: "${SHUTDOWN_WAIT_TIMEOUT:=90}"
: "${SHUTDOWN_TERM_WAIT:=10}"
: "${SHUTDOWN_SAVE_WAIT_SECONDS:=3}"
: "${RCON_STOP_LOCK_WAIT_TIMEOUT:=30}"

json_escape() {
  local s="$*"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

# Put the lock on ephemeral filesystem (NOT on /data / PVC)
RCON_STOP_RESULT=1
RCON_STOP_LOCK="${RCON_STOP_LOCK:-/tmp/.rcon-stop.lockdir}"
RCON_STOP_IN_PROGRESS=0
SERVER_PID=""

# Single source of truth for signals (make sure there is only ONE trap)
trap 'graceful_shutdown' TERM INT QUIT

handle_command_mode "$@"
if (( COMMAND_MODE_SHIFT > 0 )); then
  shift "${COMMAND_MODE_SHIFT}" || true
fi

main() {
  log INFO "Minecraft Runtime Booting..."
  preflight
  resolve_type_auto
  detect_runtime_env
  run_runtime_phase
}

if [[ "${__SOURCED:-0}" != "1" ]]; then
  main "$@"
  exit $?
fi

eval "return 0" 2>/dev/null || true

# __VELOCITY_RUNTIME_EXEC_FOOTER__
# Fail-safe: Kubernetes requires PID 1 to stay alive.
# If the script reaches here with TYPE=velocity, start Velocity in the foreground.
if [[ "${TYPE:-}" == "velocity" ]]; then
  : "${DATA_DIR:?DATA_DIR is required}"
  if [[ ! -f "${DATA_DIR}/velocity.jar" ]]; then
    die "velocity.jar not found at ${DATA_DIR}/velocity.jar"
  fi
  log INFO "Launching Velocity (foreground, PID 1)"
  cd "${DATA_DIR}"
  exec java -jar "${DATA_DIR}/velocity.jar"
fi
