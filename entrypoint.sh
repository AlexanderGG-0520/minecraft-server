#!/usr/bin/env bash
set -Eeuo pipefail

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] [$1] $2"; }
die() { log ERROR "$1"; exit 1; }

MC_PID=""

# ================================
# Force IPv4 (IMPORTANT)
# ================================
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} \
-Djava.net.preferIPv4Stack=true \
-Djava.net.preferIPv4Addresses=true"

echo "[INFO] JAVA_TOOL_OPTIONS=${JAVA_TOOL_OPTIONS}"

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
: "${TYPE:=auto}"
: "${READY_DELAY:=5}"

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
: "${MODS_REMOVE_EXTRA:=true}"

# Plugins
: "${PLUGINS_ENABLED:=true}"
: "${PLUGINS_S3_PREFIX:=plugins/latest}"
: "${PLUGINS_SYNC_ONCE:=true}"
: "${PLUGINS_REMOVE_EXTRA:=true}"

# Configs
: "${CONFIGS_ENABLED:=true}"
: "${CONFIGS_S3_PREFIX:=configs/latest}"
: "${CONFIGS_SYNC_ONCE:=true}"
: "${CONFIGS_REMOVE_EXTRA:=true}"

# Datapacks
: "${DATAPACKS_ENABLED:=true}"
: "${DATAPACKS_S3_PREFIX:=datapacks/latest}"
: "${DATAPACKS_SYNC_ONCE:=true}"
: "${DATAPACKS_REMOVE_EXTRA:=true}"

# Resourcepacks
: "${RESOURCEPACKS_ENABLED:=true}"
: "${RESOURCEPACKS_S3_PREFIX:=resourcepacks/latest}"
: "${RESOURCEPACKS_SYNC_ONCE:=true}"
: "${RESOURCEPACKS_REMOVE_EXTRA:=true}"
: "${RESOURCEPACKS_AUTO_APPLY:=true}"
: "${RESOURCEPACK_REQUIRED:=false}"

# F-3: C2ME (EXPERIMENTAL)
: "${ENABLE_C2ME:=false}"
: "${ENABLE_C2ME_HARDWARE_ACCELERATION:=false}"
: "${I_KNOW_C2ME_IS_EXPERIMENTAL:=false}"

# RCON
: "${ENABLE_RCON:=true}"
: "${RCON_HOST:=127.0.0.1}"
: "${RCON_PORT:=25575}"
: "${RCON_PASSWORD:=changeme}"


# ============================================================
# Input directories (external / immutable)
# ============================================================
: "${INPUT_MODS_DIR:=/mods}"
: "${INPUT_PLUGINS_DIR:=/plugins}"
: "${INPUT_CONFIG_DIR:=/config}"
: "${INPUT_DATAPACKS_DIR:=/datapacks}"
: "${INPUT_RESOURCEPACKS_DIR:=/resourcepacks}"
# ============================================================

# RCON
: "${ENABLE_RCON:=true}"
: "${RCON_PORT:=25575}"
: "${RCON_PASSWORD:=changeme}"
: "${STOP_SERVER_ANNOUNCE_DELAY:=0}"
# ============================================================

# Server Icon
: "${SERVER_ICON_URL:=}"
# ============================================================

preflight() {
  log INFO "Preflight checks..."

  [[ -d "${DATA_DIR}" ]] || die "${DATA_DIR} does not exist"
  touch ${DATA_DIR}/.write_test 2>/dev/null || die "${DATA_DIR} is not writable"
  rm -f ${DATA_DIR}/.write_test

  [[ -n "${EULA:-}" ]] || die "EULA is not set"

  case "${TYPE:-vanilla}" in
    fabric|forge|mohist|neoforge|paper|purpur|quilt|taiyitist|vanilla|velocity|youer) ;;
    *) die "Invalid TYPE: ${TYPE}" ;;
  esac

  if [[ "${TYPE:-vanilla}" != "vanilla" && -z "${VERSION:-}" ]]; then
    die "VERSION must be set when TYPE is not vanilla"
  fi

  rm -f ${DATA_DIR}/.ready
  log INFO "Preflight OK"
}

# ============================================================
# F-2: Runtime Environment Detection
# ============================================================

detect_runtime_env() {
  log INFO "Detecting runtime environment..."

  # ---- OS ----
  if [[ -f /etc/os-release ]]; then
    RUNTIME_OS="$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
    RUNTIME_OS_VERSION="$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
  else
    RUNTIME_OS="unknown"
    RUNTIME_OS_VERSION="unknown"
  fi
  export RUNTIME_OS RUNTIME_OS_VERSION
}


# ============================================================
# F-3: C2ME Hardware Accelerated (EXPERIMENTAL)
# ============================================================

should_enable_c2me() {
  # ---- Explicit user consent ----
  [[ "${ENABLE_C2ME}" == "true" ]] || return 1
  [[ "${ENABLE_C2ME_HARDWARE_ACCELERATION}" == "true" ]] || return 1
  [[ "${I_KNOW_C2ME_IS_EXPERIMENTAL}" == "true" ]] || return 1

  # ---- Java guard ----
  [[ "${JAVA_MAJOR}" == "25" ]] || return 1

  # ---- Runtime guard ----
  [[ "${RUNTIME_ARCH_NORM}" == "x86_64" ]] || return 1
  [[ "${RUNTIME_CONTAINER}" == "true" ]] || return 1
  [[ "${RUNTIME_GPU}" != "none" ]] || return 1

  # ---- Device guard ----
  [[ -d /dev/dri || -e /dev/nvidia0 || -e /dev/dxg ]] || return 1

  return 0
}

install_dirs() {
  log INFO "Preparing directory structure"

  mkdir -p \
    ${DATA_DIR}/logs \
    ${DATA_DIR}/config \
    ${DATA_DIR}/world

  if [[ "${TYPE}" == "paper" || "${TYPE}" == "purpur" ]]; then
    mkdir -p ${DATA_DIR}/plugins
  fi

  if [[ "${TYPE}" == "fabric" || "${TYPE}" == "forge" || "${TYPE}" == "neoforge" ]]; then
    mkdir -p "${INPUT_MODS_DIR}"
  fi

  # Permissions check
  touch ${DATA_DIR}/logs/.perm_test 2>/dev/null || die "${DATA_DIR}/logs is not writable"
  rm -f ${DATA_DIR}/logs/.perm_test

  log INFO "Directory structure ready"
}

activate_dir() {
  local src="$1"
  local dst="$2"
  local name="$3"

  [[ -d "$src" ]] || {
    log INFO "No ${name} directory found (${src}), skipping"
    return
  }

  local parent
  parent="$(dirname "$dst")"
  local base
  base="$(basename "$dst")"

  local staging="${parent}/.${base}.staging"
  local backup="${parent}/.${base}.old"

  log INFO "Activating ${name} (atomic) (${src} -> ${dst})"

  # 1. prepare staging
  rm -rf "$staging"
  mkdir -p "$staging"

  # 2. sync into staging (delete OK here)
  rsync -a --delete "$src"/ "$staging"/

  # 3. atomic switch
  if [[ -d "$dst" ]]; then
    rm -rf "$backup"
    mv "$dst" "$backup"
  fi

  mv "$staging" "$dst"

  # 4. cleanup backup
  rm -rf "$backup"
}

install_eula() {
  log INFO "Handling EULA"

  case "${EULA}" in
    true)
      echo "eula=true" > ${DATA_DIR}/eula.txt
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
cleaer_fabric_cache() {
# -----------------------------
# Clean Fabric mapping cache
# -----------------------------
case "${TYPE}" in
  fabric|taiyitist|quilt)
    log INFO "Cleaning Fabric mapping/cache directories (TYPE=${TYPE})"
    rm -rf "${DATA_DIR}/.fabric" \
           "${DATA_DIR}/.cache" \
           "${DATA_DIR}/.mappings"
    log INFO "Fabric mapping/cache directories cleaned"
    ;;
esac
}

setup_server_icon() {
  if [[ -z "${SERVER_ICON_URL:-}" ]]; then
    log INFO "SERVER_ICON_URL not set, skipping server icon setup"
    return 0
  fi

  local icon_path="${DATA_DIR}/server-icon.png"

  if [[ -f "${icon_path}" ]]; then
    log INFO "server-icon.png already exists, skipping overwrite"
    return 0
  fi

  log INFO "Setting server icon from ${SERVER_ICON_URL}"

  if ! curl -fsSL "${SERVER_ICON_URL}" -o "${icon_path}"; then
    log ERROR "Failed to download server icon"
    rm -f "${icon_path}"
    return 1
  fi

  log INFO "Server icon installed: ${icon_path}"
}

normalize_toml_key() {
  echo "$1" | sed 's/[^a-zA-Z0-9_]/_/g'
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

require_yq() {
  command -v yq >/dev/null 2>&1 || die "yq is required to edit YAML configs (install yq in the image)"
}

# Apply key=value to server.properties (replace if exists, append if not)
set_server_properties_kv() {
  local file="$1" key="$2" value="$3"
  mkdir -p "$(dirname "$file")"
  touch "$file"

  # Replace only key lines without breaking comments
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
    # Use GNU sed (assuming Linux, not macOS -i'' format)
    sed -i -E "s|^[[:space:]]*(${key})[[:space:]]*=.*$|\1=${value}|g" "$file"
  else
    printf "%s=%s\n" "$key" "$value" >> "$file"
  fi
}

# Set value on YAML dot path (roughly detect true/false/number/string types)
yq_set_yaml() {
  local file="$1" path="$2" value="$3"

  require_yq
  mkdir -p "$(dirname "$file")"
  touch "$file"

  # Keep type-like values as-is, treat others as strings
  if [[ "$value" =~ ^(true|false|null)$ ]] || [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    yq -i ".${path} = ${value}" "$file"
  else
    # Escape double quotes
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    yq -i ".${path} = \"${value}\"" "$file"
  fi
}

# Apply one "file:path=value" item
apply_paper_override_item() {
  local base_dir="$1" item="$2"
  item="$(trim_ws "$item")"
  [[ -n "$item" ]] || return 0

  local left="${item%%=*}"
  local value="${item#*=}"

  local file="${left%%:*}"
  local path="${left#*:}"

  file="$(trim_ws "$file")"
  path="$(trim_ws "$path")"
  value="$(trim_ws "$value")"

  [[ -n "$file" && -n "$path" && "$left" == *":"* && "$item" == *"="* ]] \
    || die "Invalid PAPER_CONFIG_OVERRIDES item: '${item}' (expected file:path=value)"

  local target="${base_dir}/${file}"

  # Only server.properties is treated as properties file (path=key)
  if [[ "${file}" == "server.properties" ]]; then
    set_server_properties_kv "$target" "$path" "$value"
    return 0
  fi

  # Treat other files as YAML (can add more branches by filename if needed)
  yq_set_yaml "$target" "$path" "$value"
}

configure_paper_configs() {
  is_true "${TYPE:-!paper}" || return 0

  local cfg_dir="${PAPER_CONFIG_DIR:-${DATA_DIR}/config}"
  mkdir -p "$cfg_dir"

  if is_true "${PAPER_VELOCITY:-false}"; then
    local secret="${PAPER_VELOCITY_SECRET:-${VELOCITY_SECRET:-}}"
    [[ -n "$secret" ]] || die "PAPER_VELOCITY=true but no PAPER_VELOCITY_SECRET or VELOCITY_SECRET"

    # Always write these; yq_set_yaml assumes touch/creation
    yq_set_yaml "${cfg_dir}/paper-global.yml" "proxies.velocity.enabled" "true"
    yq_set_yaml "${cfg_dir}/paper-global.yml" "proxies.velocity.secret" "$secret"

    # Do the same for legacy setups (regardless of file presence)
    yq_set_yaml "${cfg_dir}/paper.yml" "settings.velocity-support.enabled" "true"
    yq_set_yaml "${cfg_dir}/paper.yml" "settings.velocity-support.secret" "$secret"

    yq_set_yaml "${cfg_dir}/spigot.yml" "settings.bungeecord" "true"
  fi

  if [[ -n "${PAPER_CONFIG_OVERRIDES:-}" ]]; then
    local -a items
    IFS=',' read -ra items <<< "${PAPER_CONFIG_OVERRIDES}"
    local it
    for it in "${items[@]}"; do
      apply_paper_override_item "$cfg_dir" "$it"
    done
  fi

  log INFO "Paper configs applied under: ${cfg_dir}"
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

generate_velocity_toml() {
  [[ "${TYPE:-}" == "velocity" ]] || return 0

  local CONFIG_FILE="${DATA_DIR}/velocity.toml"

  rm -f "${CONFIG_FILE}"

  [[ -n "${VELOCITY_SERVERS:-}" ]] || die "VELOCITY_SERVERS is required"
  [[ -n "${VELOCITY_SECRET:-}"  ]] || die "VELOCITY_SECRET is required"

  log INFO "Generating velocity.toml"

  # For checking servers existence (not needed if declared externally, but safer this way)
  declare -gA VELOCITY_SERVER_KEYS 2>/dev/null || true
  VELOCITY_SERVER_KEYS=()

  {
    # -------------------------
    # Core settings
    # -------------------------
    cat <<EOF
bind = "${VELOCITY_BIND:-0.0.0.0:25577}"
motd = "${VELOCITY_MOTD:-<gold>Velocity</gold>}"
online-mode = ${VELOCITY_ONLINE_MODE:-true}

player-info-forwarding-mode = "modern"
forwarding-secret = "${VELOCITY_SECRET}"

EOF

    # -------------------------
    # Servers
    # -------------------------
    echo "[servers]"

    local raw_key val key entry
    local -a ENTRIES
    IFS=',' read -ra ENTRIES <<< "${VELOCITY_SERVERS}"

    local last_raw_key=""
    for entry in "${ENTRIES[@]}"; do
      entry="$(trim_ws "$entry")"
      [[ -n "$entry" ]] || continue

      raw_key="$(trim_ws "${entry%%=*}")"
      val="$(trim_ws "${entry#*=}")"

      [[ -n "$raw_key" && -n "$val" && "$entry" == *"="* ]] \
        || die "Invalid VELOCITY_SERVERS entry: '${entry}' (expected name=host:port)"

      key="$(normalize_toml_key "${raw_key}")"

      # Minimal escaping for Velocity TOML output (" and \\)
      val="${val//\\/\\\\}"
      val="${val//\"/\\\"}"

      echo "  ${key} = \"${val}\""
      VELOCITY_SERVER_KEYS["${key}"]=1

      last_raw_key="${raw_key}"
    done

    [[ -n "${last_raw_key}" ]] || die "VELOCITY_SERVERS parsed empty (check commas/spaces)"

    # -------------------------
    # Try (fallback)
    # -------------------------
    echo

    local try_src try_entry try_key
    local -a TRY_ENTRIES TRY_KEYS

    # If not specified, use last server as default (maintain original behavior)
    try_src="${VELOCITY_TRY:-${last_raw_key}}"

    IFS=',' read -ra TRY_ENTRIES <<< "${try_src}"
    for try_entry in "${TRY_ENTRIES[@]}"; do
      try_entry="$(trim_ws "$try_entry")"
      [[ -n "$try_entry" ]] || continue

      try_key="$(normalize_toml_key "${try_entry}")"

      [[ -n "${VELOCITY_SERVER_KEYS[${try_key}]:-}" ]] \
        || die "VELOCITY_TRY '${try_key}' is not defined in VELOCITY_SERVERS"

      TRY_KEYS+=("${try_key}")
    done

    [[ "${#TRY_KEYS[@]}" -gt 0 ]] || die "VELOCITY_TRY parsed empty (check commas/spaces)"

    # TOML array: try = [ "a", "b" ]
    printf 'try = [ '
    local i
    for i in "${!TRY_KEYS[@]}"; do
      [[ $i -gt 0 ]] && printf ', '
      printf '"%s"' "${TRY_KEYS[$i]}"
    done
    printf ' ]\n'

    # -------------------------
    # Forced hosts
    # -------------------------
    echo
    echo "[forced-hosts]"

    if [[ -n "${VELOCITY_FORCED_HOSTS:-}" ]]; then
      local -a HOSTS
      local h domain srv_raw srv
      IFS=',' read -ra HOSTS <<< "${VELOCITY_FORCED_HOSTS}"

      for h in "${HOSTS[@]}"; do
        h="$(trim_ws "$h")"
        [[ -n "$h" ]] || continue

        domain="$(trim_ws "${h%%:*}")"
        srv_raw="$(trim_ws "${h#*:}")"

        [[ -n "$domain" && -n "$srv_raw" && "$h" == *":"* ]] \
          || die "Invalid VELOCITY_FORCED_HOSTS item: '${h}' (expected domain:server)"

        srv="$(normalize_toml_key "${srv_raw}")"

        [[ -n "${VELOCITY_SERVER_KEYS[${srv}]:-}" ]] \
          || die "forced-host '${domain}' refers to unknown server '${srv}'"

        echo "  \"${domain}\" = [ \"${srv}\" ]"
      done
    fi
  } > "${CONFIG_FILE}"

  log INFO "velocity.toml generated"
}

ensure_server_properties() {
  local props="${DATA_DIR}/server.properties"

  if [[ ! -f "$props" ]]; then
    log INFO "server.properties not found, creating empty placeholder"
    touch "$props"
  fi
}

reset_world() {
  log INFO "Requested world reset"

  FLAG_FILE="${DATA_DIR}/reset-world.flag"  # flag file path

  # ---- Safety check 1: explicit confirmation ----
  if [[ ! -f "${FLAG_FILE}" ]]; then
    log INFO "reset-world.flag file is missing, cannot proceed with world reset"
    return  # return instead of die to avoid stopping the script
  fi

  WORLD_DIR="${DATA_DIR}/world"
  MODS_DIR="${DATA_DIR}/mods"

  # ---- Safety check 2: directory sanity ----
  if [[ ! -d "${WORLD_DIR}" ]]; then
    log INFO "World directory does not exist, nothing to reset"
    return
  fi

  if [[ "${WORLD_DIR}" == "/" || "${WORLD_DIR}" == "${DATA_DIR}" ]]; then
    log ERROR "Unsafe WORLD_DIR detected: ${WORLD_DIR}"
    return  # stop instead of die
  fi

  log INFO "Resetting world at ${WORLD_DIR}"

  # ---- Step 1: mark NotReady ----
  rm -f ${DATA_DIR}/.ready

  # ---- Step 2: optional backup ----
  if [[ "${RESET_WORLD_BACKUP:-true}" == "true" ]]; then
    TS="$(date -u +'%Y%m%d-%H%M%S')"
    BACKUP_DIR="${DATA_DIR}/backups"
    mkdir -p "${BACKUP_DIR}"

    log INFO "Creating world backup"
    tar -czf "${BACKUP_DIR}/world-${TS}.tar.gz" -C ${DATA_DIR} world \
      || log ERROR "World backup failed"
  fi

  # ---- Step 3: delete world directory completely ----
  log INFO "Deleting world directory"
  rm -rf "${WORLD_DIR}"
  mkdir -p "${WORLD_DIR}"
  rm -rf "${MODS_DIR}"
  mkdir -p "${MODS_DIR}"
  log INFO "World directory reset complete"

  # ---- Step 4: delete the FLAG file to prevent repeated resets ----
  rm -f "${FLAG_FILE}"

  log INFO "World reset completed successfully"
}

handle_reset_world_flag() {
  MAX_AGE=1800  # 30 minutes
  FLAG="${DATA_DIR}/reset-world.flag"

  if [[ -f "$FLAG" ]]; then
    NOW=$(date +%s)
    MTIME=$(stat -c %Y "$FLAG")

    if (( NOW - MTIME > MAX_AGE )); then
      log ERROR "reset-world.flag expired (older than ${MAX_AGE}s), resetting aborted"
      rm -f "$FLAG"
      return
    fi

    log WARN "reset-world.flag valid, proceeding to reset world"
    reset_world
    rm -f "$FLAG"
    log INFO "reset-world.flag consumed"
  else
    log INFO "No reset-world.flag detected, skipping world reset"
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
    vanilla|paper|purpur)
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

install_server() {
  log INFO "Resolving server (TYPE=${TYPE}, VERSION=${VERSION:-auto})"

  case "${TYPE}" in
    vanilla)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for vanilla"

      if [[ -f ${DATA_DIR}/server.jar ]]; then
        log INFO "server.jar already exists, skipping"
        return
      fi

      log INFO "Downloading vanilla server ${VERSION}"
      meta_url="$(curl -fsSL https://launchermeta.mojang.com/mc/game/version_manifest.json \
        | jq -r '.versions[] | select(.id=="'"${VERSION}"'") | .url')"
      [[ -n "${meta_url}" && "${meta_url}" != "null" ]] || die "Invalid VERSION: ${VERSION}"

      sha1="$(curl -fsSL "${meta_url}" | jq -r '.downloads.server.sha1')"
      curl -fL "https://piston-data.mojang.com/v1/objects/${sha1}/server.jar" \
        -o ${DATA_DIR}/server.jar \
        || die "Failed to download vanilla server.jar"
      ;;

    fabric)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for fabric"

      if [[ -f "${DATA_DIR}/fabric-server-launch.jar" ]]; then
        log INFO "fabric-server-launch.jar already exists, skipping"
        return
      fi

      json="$(curl -fsSL "https://meta.fabricmc.net/v2/versions/loader/${VERSION}" || true)"

      LOADER_VERSION="$(printf '%s' "$json" | jq -er '
        if type=="array" and length>0 and .[0].loader.version
        then .[0].loader.version
        else empty
        end
      ')"

      [[ -n "${LOADER_VERSION}" ]] || die "Failed to resolve Fabric loader version"


      # ---- resolve installer (from Maven) ----
      INSTALLER_VERSION="${FABRIC_INSTALLER_VERSION:-latest}"
      if [[ "${INSTALLER_VERSION}" == "latest" ]]; then
        INSTALLER_VERSION="$(curl -fsSL \
          "https://maven.fabricmc.net/net/fabricmc/fabric-installer/maven-metadata.xml" \
          | tr -d '\r' \
          | grep -oPm1 '(?<=<latest>)[^<]+')" \
          || die "Failed to resolve Fabric installer version"
      fi

      log INFO "Installing Fabric server (MC=${VERSION}, loader=${LOADER_VERSION}, installer=${INSTALLER_VERSION})"

      curl -fL \
        "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${INSTALLER_VERSION}/fabric-installer-${INSTALLER_VERSION}.jar" \
        -o /tmp/fabric-installer.jar \
        || die "Failed to download Fabric installer"

      java -jar /tmp/fabric-installer.jar \
        server \
        -mcversion "${VERSION}" \
        -loader "${LOADER_VERSION}" \
        -downloadMinecraft \
        -dir "${DATA_DIR}" \
        || die "Fabric installer failed"

      log INFO "Fabric server.jar ready"
      ;;

    quilt)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for quilt"

      if [[ -f "${DATA_DIR}/server.jar" ]]; then
        log INFO "server.jar already exists, skipping"
        return
      fi

      log INFO "Installing Quilt server ${VERSION}"

      curl -fL \
        "https://meta.quiltmc.org/v3/versions/loader/${VERSION}/latest/server/jar" \
        -o "${DATA_DIR}/server.jar" \
        || die "Failed to download Quilt server.jar"

      log INFO "Quilt server.jar ready"
      ;;

    forge)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for forge"

      FORGE_VER="${FORGE_VERSION:-latest}"
      FORGE_META_URL="https://files.minecraftforge.net/net/minecraftforge/forge/index_${VERSION}.html"

      # ---- resolve version FIRST ----
      if [[ "${FORGE_VER}" == "latest" ]]; then
        log INFO "Resolving latest Forge version for MC ${VERSION}"

        html="$(curl -fsSL "${FORGE_META_URL}" || true)"

        FORGE_VER="$(printf '%s' "$html" \
          | grep -oP 'forge-\K[0-9.]+' \
          | head -n 1)"

        [[ -n "${FORGE_VER}" ]] || {
          log ERROR "Failed to resolve Forge version. Response was:"
          log ERROR "$(echo "$html" | head -c 300)"
          die "Invalid Forge version"
        }
      fi

      # ---- sanity check ----
      [[ -n "${FORGE_VER}" && "${FORGE_VER}" != "null" ]] \
        || die "Invalid Forge version resolved: ${FORGE_VER}"

      MARKER="${DATA_DIR}/.installed-forge-${VERSION}-${FORGE_VER}"

      if [[ -f "${MARKER}" ]]; then
        log INFO "Forge already installed (MC=${VERSION}, forge=${FORGE_VER}), skipping"
      else
        log INFO "Installing Forge server (MC=${VERSION}, forge=${FORGE_VER})"

        INSTALLER="forge-${VERSION}-${FORGE_VER}-installer.jar"
        curl -fL \
          "https://maven.minecraftforge.net/net/minecraftforge/forge/${VERSION}-${FORGE_VER}/${INSTALLER}" \
          -o "/tmp/${INSTALLER}" \
          || die "Failed to download Forge installer"

        java -jar "/tmp/${INSTALLER}" --installServer "${DATA_DIR}" \
          || die "Forge installer failed"

        [[ -x "${DATA_DIR}/run.sh" ]] || die "Forge install finished but run.sh not found"

        touch "${MARKER}"
        log INFO "Forge installed marker created: ${MARKER}"
      fi
      ;;

    neoforge)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for neoforge"

      NEO_VER="${NEOFORGE_VERSION:-latest}"
      META_URL="https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge"

      if [[ -z "$NEO_VER" || "$NEO_VER" == "latest" ]]; then
        log INFO "Resolving latest NeoForge (non-craftmine only)"
        json="$(curl -fsSL "$META_URL")"

        NEO_VER="$(
          printf '%s' "$json" | jq -r '
            .versions[]
            | select(test("craftmine") | not)
            | select(test("^21\\.1\\."))
          ' | head -n 1
        )"
      fi

      MARKER="${DATA_DIR}/.installed-neoforge-${VERSION}-${NEO_VER}"

      if [[ -f "${MARKER}" ]]; then
        log INFO "NeoForge already installed (MC=${VERSION}, neoforge=${NEO_VER}), skipping"
      else
        log INFO "Installing NeoForge server (MC=${VERSION}, neoforge=${NEO_VER})"

        INSTALLER="neoforge-${NEO_VER}-installer.jar"
        curl -fL \
          "https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEO_VER}/${INSTALLER}" \
          -o "/tmp/${INSTALLER}" \
          || die "Failed to download NeoForge installer"

        java -jar "/tmp/${INSTALLER}" --installServer "${DATA_DIR}" \
          || die "NeoForge installer failed"

        [[ -x "${DATA_DIR}/run.sh" ]] || die "NeoForge install finished but run.sh not found"

        touch "${MARKER}"
        log INFO "NeoForge installed marker created: ${MARKER}"
      fi
      ;;

    paper)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for paper"

      if [[ -f ${DATA_DIR}/server.jar ]]; then
        log INFO "server.jar already exists, skipping"
        return
      fi

      BUILD="${PAPER_BUILD:-latest}"

      log INFO "Installing Paper server (MC=${VERSION}, build=${BUILD})"

      if [[ "${BUILD}" == "latest" ]]; then
        log INFO "Resolving latest Paper build for MC ${VERSION}"

        json="$(curl -fsSL \
          "https://api.papermc.io/v2/projects/paper/versions/${VERSION}" || true)"

        BUILD="$(printf '%s' "$json" | jq -er '
          if has("builds")
            and (.builds|type=="array")
            and (.builds|length>0)
          then .builds[-1]
          else empty
          end
        ')"

        [[ -n "${BUILD}" ]] || {
          log ERROR "Failed to resolve Paper build. Response was:"
          log ERROR "$(echo "$json" | head -c 300)"
          die "Invalid Paper build"
        }
      fi

      JAR_NAME="paper-${VERSION}-${BUILD}.jar"

      curl -fL \
        "https://api.papermc.io/v2/projects/paper/versions/${VERSION}/builds/${BUILD}/downloads/${JAR_NAME}" \
        -o ${DATA_DIR}/server.jar \
        || die "Failed to download Paper server.jar"

      log INFO "Paper server.jar ready"
      ;;
    
    purpur)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for purpur"

      if [[ -f ${DATA_DIR}/server.jar ]]; then
        log INFO "server.jar already exists, skipping"
        return
      fi

      BUILD="${PURPUR_BUILD:-latest}"

      if [[ "${BUILD}" == "latest" ]]; then
        log INFO "Resolving latest Purpur build for MC ${VERSION}"

        json="$(curl -fsSL "https://api.purpurmc.org/v2/purpur/${VERSION}" || true)"

        BUILD="$(printf '%s' "$json" | jq -er '
          if has("builds")
            and (.builds|type=="object")
            and (.builds|has("latest"))
          then .builds.latest
          else empty
          end
        ')"

        [[ -n "${BUILD}" ]] || {
          log ERROR "Failed to resolve Purpur build. Response was:"
          log ERROR "$(echo "$json" | head -c 300)"
          die "Invalid Purpur build"
        }
      fi

      JAR_NAME="purpur-${VERSION}-${BUILD}.jar"

      curl -fL \
        "https://api.purpurmc.org/v2/purpur/${VERSION}/${BUILD}/download" \
        -o ${DATA_DIR}/server.jar \
        || die "Failed to download Purpur server.jar"

      log INFO "Purpur server.jar ready"
      ;;

    mohist)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for mohist"

      if [[ -f "${DATA_DIR}/server.jar" ]]; then
        log INFO "server.jar already exists, skipping"
        return
      fi

      log INFO "Installing Mohist server ${VERSION}"

      curl -fL \
        "https://mohistmc.com/api/v2/projects/mohist/${VERSION}/builds/latest/download" \
        -o "${DATA_DIR}/server.jar" \
        || die "Failed to download Mohist server.jar"

      log INFO "Mohist server.jar ready"
      ;;

    taiyitist)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for taiyitist"

      if [[ -f "${DATA_DIR}/server.jar" ]]; then
        log INFO "server.jar already exists, skipping"
        return
      fi

      log INFO "Resolving Taiyitist ${VERSION} release asset"

      TAIYITIST_VERSION="${VERSION}-release"

      ASSET_URL=$(
        curl -fsSL "https://api.github.com/repos/TaiyitistMC/Taiyitist/releases/tags/${TAIYITIST_VERSION}" \
          | grep browser_download_url \
          | grep taiyitist-server \
          | cut -d '"' -f 4
      )

      [[ -n "${ASSET_URL}" ]] || die "Failed to resolve Taiyitist release asset"

      log INFO "Downloading ${ASSET_URL}"

      curl -fL "${ASSET_URL}" -o "${DATA_DIR}/server.jar" \
        || die "Failed to download Taiyitist server.jar"

      log INFO "Taiyitist server.jar ready"
      ;;

    youer)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for youer"

      if [[ -f "${DATA_DIR}/server.jar" ]]; then
        log INFO "server.jar already exists, skipping"
        return
      fi

      log INFO "Installing Youer server ${VERSION}"

      curl -fL \
        "https://api.youer.org/v1/projects/youer/${VERSION}/builds/latest/download" \
        -o "${DATA_DIR}/server.jar" \
        || die "Failed to download Youer server.jar"

      log INFO "Youer server.jar ready"
      ;;

    velocity)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for velocity"
      generate_velocity_toml

      if [[ -f "${DATA_DIR}/velocity.jar" ]]; then
        log INFO "velocity.jar already exists, skipping"
        return
      fi

      log INFO "Resolving Velocity ${VERSION} build"

      BUILD=$(curl -fsSL \
        "https://api.papermc.io/v2/projects/velocity/versions/${VERSION}" \
        | jq -r '.builds[-1]') \
        || die "Failed to resolve Velocity build"

      log INFO "Installing Velocity ${VERSION} build ${BUILD}"

      curl -fL \
        "https://api.papermc.io/v2/projects/velocity/versions/${VERSION}/builds/${BUILD}/downloads/velocity-${VERSION}-${BUILD}.jar" \
        -o "${DATA_DIR}/velocity.jar" \
        || die "Failed to download Velocity jar"

      log INFO "Velocity jar ready"
      ;;
    *)
      die "install_server: TYPE=${TYPE} not implemented yet"
      ;;
  esac
}

install_server_properties() {
  local props="${DATA_DIR}/server.properties"

  log INFO "Ensuring server.properties exists"

  # ------------------------------------------------------------
  # Fast path: already exists
  # ------------------------------------------------------------
  if [[ -f "$props" ]]; then
    log INFO "server.properties already exists, skipping bootstrap"
    return 0
  fi

  log INFO "server.properties not found, bootstrapping via official server startup"

  # ------------------------------------------------------------
  # Safety: ensure required binaries exist
  # ------------------------------------------------------------
  case "${TYPE}" in
    vanilla|paper|purpur|mohist|taiyitist|youer)
      [[ -f "${DATA_DIR}/server.jar" ]] \
        || die "server.jar not found for TYPE=${TYPE}"
      ;;
    fabric)
      [[ -f "${DATA_DIR}/fabric-server-launch.jar" ]] \
        || die "fabric-server-launch.jar not found"
      ;;
    forge|neoforge)
      [[ -x "${DATA_DIR}/run.sh" ]] \
        || die "run.sh not found for TYPE=${TYPE}"
      ;;
    *)
      die "install_server_properties: unsupported TYPE=${TYPE}"
      ;;
  esac

  # ------------------------------------------------------------
  # JVM safety mode (NO parallelism, NO mods side effects)
  # ------------------------------------------------------------
  local JVM_ARGS_BAK=""
  if [[ -f "${DATA_DIR}/jvm.args" ]]; then
    JVM_ARGS_BAK="${DATA_DIR}/jvm.args.bak"
    mv "${DATA_DIR}/jvm.args" "${JVM_ARGS_BAK}"
  fi

  cat > "${DATA_DIR}/jvm.args" <<EOF
  -Xms512M
  -Xmx512M
  -Dfile.encoding=UTF-8
EOF

  # ------------------------------------------------------------
  # Bootstrap run (short-lived, no worldgen)
  # ------------------------------------------------------------
  log INFO "Starting short bootstrap run to generate server.properties"

  case "${TYPE}" in
    vanilla|paper|purpur)
      timeout 20s java @"${DATA_DIR}/jvm.args" \
        -jar "${DATA_DIR}/server.jar" nogui || true
      ;;
    fabric)
      timeout 20s java @"${DATA_DIR}/jvm.args" \
        -jar "${DATA_DIR}/fabric-server-launch.jar" nogui || true
      ;;
    forge|neoforge)
      timeout 20s "${DATA_DIR}/run.sh" nogui || true
      ;;
  esac

  # ------------------------------------------------------------
  # Restore JVM args
  # ------------------------------------------------------------
  rm -f "${DATA_DIR}/jvm.args"
  if [[ -n "${JVM_ARGS_BAK}" ]]; then
    mv "${JVM_ARGS_BAK}" "${DATA_DIR}/jvm.args"
  fi

  # ------------------------------------------------------------
  # Final verification
  # ------------------------------------------------------------
  if [[ ! -f "$props" ]]; then
    die "server.properties still not generated after bootstrap"
  fi

  log INFO "server.properties successfully generated"
}

install_mods() {
  log INFO "Install mods (MinIO only)"

  [[ "${MODS_ENABLED:-true}" == "true" ]] || {
    log INFO "Mods disabled"
    return
  }

  [[ -n "${MODS_S3_BUCKET:-}" ]] || {
    log INFO "MODS_S3_BUCKET not set, skipping mods"
    return
  }

  MODS_DIR="${INPUT_MODS_DIR}"
  mkdir -p "${MODS_DIR}"

  if [[ "${MODS_SYNC_ONCE}" == "true" ]] \
    && [[ -n "$(ls -A "${MODS_DIR}")" ]] \
    && [[ "${MODS_REMOVE_EXTRA}" != "true" ]]; then
    log INFO "Mods already present, skipping sync"
    return
  fi


  log INFO "Configuring MinIO client"
  mc alias set s3 \
    "${S3_ENDPOINT}" \
    "${S3_ACCESS_KEY}" \
    "${S3_SECRET_KEY}" \
    || die "Failed to configure MinIO client"

  REMOVE_FLAG=""
  [[ "${MODS_REMOVE_EXTRA}" == "true" ]] && REMOVE_FLAG="--remove"

  log INFO "Syncing mods from s3://${MODS_S3_BUCKET}/${MODS_S3_PREFIX}"

  mc mirror \
    --overwrite \
    ${REMOVE_FLAG} \
    "s3/${MODS_S3_BUCKET}/${MODS_S3_PREFIX}" \
    "${MODS_DIR}" \
    || die "Failed to sync mods from MinIO"

  shopt -s nullglob
  jars=("${MODS_DIR}"/*.jar)
  log INFO "Mods installed: ${#jars[@]}"
  shopt -u nullglob
}

activate_mods() {
  activate_dir "/mods" "${DATA_DIR}/mods" "mods"
}

detect_optimize_mod() {
  local name="$1"
  ls "${DATA_DIR}/mods"/"${name}"*.jar >/dev/null 2>&1
}

has_c2me_mod() {
  detect_optimize_mod "c2me"
}

install_jvm_args() {
  log INFO "Generating JVM args"

  JVM_ARGS_FILE="${DATA_DIR}/jvm.args"

  # skip if already exists
  if [[ -f "${JVM_ARGS_FILE}" ]]; then
    log INFO "jvm.args already exists, skipping generation"
    return
  fi

  : "${JVM_XMS:=512M}"
  : "${JVM_XMX:=512M}"
  : "${JVM_GC:=G1}"
  : "${JVM_EXTRA_ARGS:=}"

  {
    echo "-Xms${JVM_XMS}"
    echo "-Xmx${JVM_XMX}"

    case "${JVM_GC}" in
      G1)
        echo "-XX:+UseG1GC"
        ;;
      ZGC)
        echo "-XX:+UseZGC"
        ;;
      *)
        die "Invalid JVM_GC: ${JVM_GC}"
        ;;
    esac

    if [[ "${JVM_USE_CONTAINER_SUPPORT:-true}" == "true" ]]; then
      echo "-XX:+UseContainerSupport"
    fi

    if [[ -n "${JVM_EXTRA_ARGS}" ]]; then
      echo "${JVM_EXTRA_ARGS}"
    fi
  } > "${JVM_ARGS_FILE}"

  log INFO "jvm.args generated"
}

install_c2me_jvm_args() {
  if ! has_c2me_mod; then
    log INFO "C2ME mod not found in mods/, skipping"
    return 0
  fi

  if ! detect_gpu; then
    log INFO "CPU-only environment detected, skipping ALL C2ME optimizations"
    return 0
  fi

  if should_enable_c2me; then
    log WARN "C2ME Hardware Acceleration ENABLED (EXPERIMENTAL)"
    log WARN "This may cause instability or data corruption"

    {
      echo ""
      echo "# --- C2ME Hardware Acceleration (EXPERIMENTAL) ---"
      echo "-Dc2me.experimental.hardwareAcceleration=true"
      echo "-Dc2me.experimental.opencl=true"
      echo "-Dc2me.experimental.unsafe=true"
    } >> /data/jvm.args
  else
    log INFO "C2ME mod present, but guard conditions not met"
  fi
}

install_configs() {
  log INFO "Install configs (MinIO only)"

  [[ "${CONFIGS_ENABLED:-true}" == "true" ]] || {
    log INFO "Configs disabled"
    return
  }

  [[ -n "${CONFIGS_S3_BUCKET:-}" ]] || {
    log INFO "CONFIGS_S3_BUCKET not set, skipping configs"
    return
  }

  CONFIG_DIR="${INPUT_CONFIG_DIR:-/config}"
  mkdir -p "${CONFIG_DIR}"

  # now already configs present and sync once mode, skipping
  if [[ "${CONFIGS_SYNC_ONCE}" == "true" ]] \
    && [[ -n "$(ls -A "${CONFIG_DIR}")" ]] \
    && [[ "${CONFIGS_REMOVE_EXTRA}" != "true" ]]; then
    log INFO "Configs already present, skipping sync"
    return
  fi


  log INFO "Configuring MinIO client for configs"
  mc alias set s3 \
    "${S3_ENDPOINT}" \
    "${S3_ACCESS_KEY}" \
    "${S3_SECRET_KEY}" \
    || die "Failed to configure MinIO client"


  REMOVE_FLAG=""
  [[ "${CONFIGS_REMOVE_EXTRA}" == "true" ]] && REMOVE_FLAG="--remove"

  log INFO "Syncing configs from s3://${CONFIGS_S3_BUCKET}/${CONFIGS_S3_PREFIX}"

  mc mirror \
    --overwrite \
    ${REMOVE_FLAG} \
    "s3/${CONFIGS_S3_BUCKET}/${CONFIGS_S3_PREFIX}" \
    "${CONFIG_DIR}" \
    || die "Failed to sync configs from MinIO"

  log INFO "Configs installed successfully"
}

activate_configs() {
  activate_dir "/config" "${DATA_DIR}/config" "config"
}

# --- YAML helper: escape a string for double-quoted YAML scalars ---
yaml_escape_dq() {
  local s="$1"
  s="${s//\\/\\\\}"   # \  -> \\
  s="${s//\"/\\\"}"   # "  -> \"
  printf '%s' "$s"
}

# --- Paper: apply config/paper-global.yml from environment variables ---
# Expected ENV:
#   PAPER_VELOCITY=true
#   PAPER_VELOCITY_SECRET=<must match Velocity forwarding.secret>
#
# Fallback:
#   If PAPER_VELOCITY_SECRET is empty, VELOCITY_SECRET is used.
#
# Optional:
#   PAPER_VELOCITY_ONLINE_MODE=true|false (usually true)
#   PAPER_VELOCITY_ENABLED=true|false (usually true)
apply_paper_global_from_env() {
  is_true "${TYPE:-!paper}" || return 0
  is_true "${PAPER_VELOCITY:-false}" || return 0

  local cfg_dir="${PAPER_CONFIG_DIR:-${DATA_DIR}/config}"
  local file="${cfg_dir}/paper-global.yml"

  local enabled="${PAPER_VELOCITY_ENABLED:-true}"
  local online_mode="${PAPER_VELOCITY_ONLINE_MODE:-true}"
  local secret="${PAPER_VELOCITY_SECRET:-${VELOCITY_SECRET:-}}"

  [[ -n "$secret" ]] || die "PAPER_VELOCITY=true but no PAPER_VELOCITY_SECRET (or VELOCITY_SECRET)"

  mkdir -p "$cfg_dir"
  touch "$file"

  # If yq is available, update only the required keys without destroying other settings.
  if command -v yq >/dev/null 2>&1; then
    yq -i ".proxies.velocity.enabled = ${enabled}" "$file"
    yq -i ".proxies.velocity.online-mode = ${online_mode}" "$file"
    yq -i ".proxies.velocity.secret = \"$(yaml_escape_dq "$secret")\"" "$file"
    log INFO "paper-global.yml updated via yq: $file"
    return 0
  fi

  # If yq is not available, generate a minimal file via tee (this overwrites the file).
  log WARN "yq not found; generating minimal paper-global.yml via tee (overwrites file): $file"
  cat <<EOF | tee "$file" >/dev/null
proxies:
  velocity:
    enabled: ${enabled}
    online-mode: ${online_mode}
    secret: "$(yaml_escape_dq "$secret")"
EOF
  log INFO "paper-global.yml generated via tee: $file"
}

install_plugins() {
  log INFO "Install plugins (Paper | Purpur | Mohist | Taiyitist | Youer | Velocity only)"

  [[ "${PLUGINS_ENABLED:-true}" == "true" ]] || { log INFO "Plugins disabled"; return 0; }

  if [[ "${TYPE:-auto}" != "paper" ]] \
    && [[ "${TYPE:-auto}" != "purpur" ]] \
    && [[ "${TYPE:-auto}" != "mohist" ]] \
    && [[ "${TYPE:-auto}" != "taiyitist" ]] \
    && [[ "${TYPE:-auto}" != "youer" ]] \
    && [[ "${TYPE:-auto}" != "velocity" ]]; then
    log INFO "TYPE=${TYPE}, skipping plugins"
    return 0
  fi

  [[ -n "${PLUGINS_S3_BUCKET:-}" ]] || { log INFO "PLUGINS_S3_BUCKET not set, skipping plugins"; return 0; }

  local plugins_dir="${INPUT_PLUGINS_DIR}"
  mkdir -p "${plugins_dir}"

  # -----------------------------------
  # Stability knobs (Cloudflare Tunnel friendly)
  # -----------------------------------
  local retry_max="${MC_RETRY_MAX:-8}"     # 6-10 recommended
  local retry_base="${MC_RETRY_SLEEP:-1}"  # seconds (1,2,4,8...)
  local strict="${PLUGINS_STRICT:-false}"  # true: die on any error, false: best-effort
  local max_errors="${PLUGINS_MAX_ERRORS:-50}"

  local tmp_remote=""
  local tmp_remote_jars=""

  cleanup_plugins_tmp() {
    rm -f -- "${tmp_remote:-}" "${tmp_remote_jars:-}" 2>/dev/null || true
  }
  trap cleanup_plugins_tmp RETURN

  tmp_remote="$(mktemp)"
  tmp_remote_jars="$(mktemp)"

  mc_retry() {
    local n=0
    while true; do
      "$@" && return 0
      n=$((n+1))
      if (( n >= retry_max )); then
        return 1
      fi
      local s=$((retry_base << (n-1)))
      log WARN "mc failed (attempt ${n}/${retry_max}), retry in ${s}s: $*"
      sleep "${s}"
    done
  }

  log INFO "Configuring MinIO client for plugins"
  mc alias set s3 "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}" \
    || die "Failed to configure MinIO client"

  # Build source path safely
  local src="s3/${PLUGINS_S3_BUCKET}"
  if [[ -n "${PLUGINS_S3_PREFIX:-}" ]]; then
    src="${src%/}/${PLUGINS_S3_PREFIX}"
  fi
  src="${src%/}/"  # ensure trailing slash

  # Skip condition (optional behavior)
  if [[ "${PLUGINS_SYNC_ONCE:-false}" == "true" ]] \
    && [[ -n "$(ls -A "${plugins_dir}" 2>/dev/null)" ]] \
    && [[ "${PLUGINS_REMOVE_EXTRA:-false}" != "true" ]]; then
    log INFO "Plugins already present, skipping sync (PLUGINS_SYNC_ONCE=true)"
    return 0
  fi

  log INFO "Syncing plugins from ${src} -> ${plugins_dir}"
  log INFO "Policy: sync top-level .jar only (no subdirectories)"
  log INFO "Safety: never touch .paper-remapped/, remove_extra only when sync has 0 errors, and only plugins/*.jar"

  # -----------------------------------
  # Temp files (safe under `set -u`)
  # -----------------------------------
  local tmp_remote=""         # list of all remote objects
  local tmp_remote_topjars="" # list of remote top-level jars (plugins/*.jar only)

  cleanup_plugins_tmp() {
    rm -f -- "${tmp_remote:-}" "${tmp_remote_topjars:-}" 2>/dev/null || true
  }
  trap cleanup_plugins_tmp RETURN

  tmp_remote="$(mktemp)"
  tmp_remote_topjars="$(mktemp)"

  # -----------------------------------
  # List remote objects once
  # -----------------------------------
  if ! mc_retry mc find "${src}" --print "{}" > "${tmp_remote}"; then
    die "Failed to list objects from MinIO"
  fi

  # Build remote "top-level jar" list for safe remove_extra (plugins/*.jar only)
  awk -v s="${src}" '
    index($0, s) == 1 {
      rel = substr($0, length(s)+1)
      # only "top-level" jars: no slash, ends with .jar
      if (rel ~ /^[^/]+\.jar$/) print rel
    }
  ' "${tmp_remote}" | sort -u > "${tmp_remote_topjars}"

  # -----------------------------------
  # Download loop (top-level jars only)
  # -----------------------------------
  local obj rel dest
  local errors=0

  while IFS= read -r obj; do
    [[ -n "${obj}" ]] || continue

    # Defensive: skip directory-like entries
    [[ "${obj}" != */ ]] || continue

    rel="${obj#${src}}"
    [[ "${rel}" != "${obj}" ]] || continue
    [[ -n "${rel}" ]] || continue

    # Only sync top-level jars
    if [[ "${rel}" != *.jar || "${rel}" == */* ]]; then
      continue
    fi

    dest="${plugins_dir}/${rel}"
    rm -f -- "${dest}" || true
    if ! mc_retry mc cp "${obj}" "${dest}"; then
      errors=$((errors+1))
      log WARN "Failed to download jar: ${obj}"
    fi

    if (( errors >= max_errors )); then
      log WARN "Too many errors while syncing plugins (${errors})."
      if [[ "${strict}" == "true" ]]; then
        die "Plugins sync exceeded error limit (${max_errors})"
      fi
      break
    fi
  done < "${tmp_remote}"

  # -----------------------------------
  # Safe remove_extra
  #  - only when sync has 0 errors
  #  - only plugins/*.jar (top-level)
  #  - never touch .paper-remapped/
  # -----------------------------------
  if [[ "${PLUGINS_REMOVE_EXTRA:-false}" == "true" ]]; then
    if (( errors == 0 )); then
      log INFO "PLUGINS_REMOVE_EXTRA=true: removing extra local top-level *.jar only (sync had 0 errors)"

      # local: only plugins/*.jar (maxdepth 1)
      while IFS= read -r local_jar; do
        [[ -n "${local_jar}" ]] || continue
        local base
        base="$(basename "${local_jar}")"

        if ! grep -Fxq "${base}" "${tmp_remote_topjars}"; then
          log INFO "Removing extra local jar: ${local_jar}"
          rm -f -- "${local_jar}" || {
            ((strict == true)) && die "Failed to remove extra jar: ${local_jar}"
            log WARN "Failed to remove extra jar (non-strict): ${local_jar}"
          }
        fi
      done < <(find "${plugins_dir}" -maxdepth 1 -type f -name "*.jar" 2>/dev/null)
    else
      log WARN "Skip PLUGINS_REMOVE_EXTRA because sync had ${errors} error(s)"
    fi
  fi

  # -----------------------------------
  # Finalize
  # -----------------------------------
  if (( errors > 0 )); then
    if [[ "${strict}" == "true" ]]; then
      die "Plugins sync failed with ${errors} error(s)"
    else
      log WARN "Plugins sync completed with ${errors} error(s) (non-strict)"
    fi
  else
    log INFO "Plugins synced successfully"
  fi

  return 0
}

activate_plugins() {
  local src="/plugins"
  local dst="${DATA_DIR}/plugins"

  log INFO "Activating plugins (merge, protect non-jar) (${src} -> ${dst})"
  mkdir -p "${dst}"

  # Safety: never touch Paper cache
  local errors=0

  # 1) Ensure directories exist (only create if missing)
  while IFS= read -r -d '' d; do
    [[ "${d}" == "." ]] && continue
    mkdir -p "${dst}/${d#./}" || true
  done < <(cd "${src}" && find . -type d ! -path './.paper-remapped*' -print0)

  # 2) Copy files with policy
  while IFS= read -r -d '' f; do
    local rel="${f#./}"
    local s="${src}/${rel}"
    local t="${dst}/${rel}"
    local td
    td="$(dirname "${t}")"
    mkdir -p "${td}"

    # Skip Paper-generated cache
    [[ "${rel}" == .paper-remapped/* ]] && continue

    if [[ "${rel}" == *.jar ]]; then
      # jar: always overwrite (atomic per-file)
      local tmp="${t}.tmp.$$"
      cp -a "${s}" "${tmp}" || { errors=$((errors+1)); log WARN "Failed to copy jar: ${s}"; continue; }
      mv -f "${tmp}" "${t}" || { errors=$((errors+1)); log WARN "Failed to move jar into place: ${t}"; continue; }
    else
      # non-jar: seed only (never overwrite)
      if [[ -e "${t}" ]]; then
        continue
      fi
      local tmp="${t}.tmp.$$"
      cp -a "${s}" "${tmp}" || { errors=$((errors+1)); log WARN "Failed to seed non-jar: ${s}"; continue; }
      mv -f "${tmp}" "${t}" || { errors=$((errors+1)); log WARN "Failed to move non-jar into place: ${t}"; continue; }
    fi
  done < <(cd "${src}" && find . -type f -print0)

  if (( errors > 0 )); then
    log WARN "activate_plugins finished with errors=${errors} (non-jar protected; jars best-effort applied)"
  else
    if [[ "${PLUGINS_REMOVE_EXTRA:-false}" == "true" ]]; then
      local tmp_src_jars=""
      tmp_src_jars="$(mktemp)"

      (cd "${src}" && find . -type f -name "*.jar" ! -path './.paper-remapped*' -print \
        | sed 's|^\./||' | sort -u > "${tmp_src_jars}")

      while IFS= read -r -d '' local_jar; do
        local rel="${local_jar#${dst}/}"
        if [[ "${rel}" == */* ]]; then
          continue
        fi
        if ! grep -Fxq "${rel}" "${tmp_src_jars}"; then
          log INFO "Removing extra jar from ${dst}: ${rel}"
          rm -f -- "${local_jar}" || log WARN "Failed to remove extra jar: ${local_jar}"
        fi
      done < <(find "${dst}" -maxdepth 1 -type f -name "*.jar" -print0)

      rm -f -- "${tmp_src_jars}"
    fi

    log INFO "activate_plugins completed (non-jar protected)"
  fi

  return 0
}

install_world() {
  local WORLD_DIR="${DATA_DIR}/world"

  # ------------------------------------------------------------
  # Guard
  # ------------------------------------------------------------
  if [[ -d "${WORLD_DIR}" && ! -f "${DATA_DIR}/reset-world.flag" ]]; then
    log INFO "World already exists, skipping world install"
    return 0
  fi

  if [[ -z "${WORLD_S3_BUCKET:-}" || -z "${WORLD_S3_KEY:-}" ]]; then
    log INFO "WORLD_S3_BUCKET or WORLD_S3_KEY not set, skipping world install"
    return 0
  fi

  log INFO "Installing world from S3"

  # ------------------------------------------------------------
  # Prepare
  # ------------------------------------------------------------
  rm -rf "${WORLD_DIR}"
  mkdir -p "${WORLD_DIR}"

  local TMP_ZIP="/tmp/world.zip"

  # ------------------------------------------------------------
  # Download
  # ------------------------------------------------------------
  mc alias set s3 "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}"

  mc cp "s3/${WORLD_S3_BUCKET}/${WORLD_S3_KEY}" "${TMP_ZIP}" \
    || die "Failed to download world archive"

  # ------------------------------------------------------------
  # Extract
  # ------------------------------------------------------------
  unzip -q "${TMP_ZIP}" -d "${DATA_DIR}"

  # Safety check if world/ is not directly inside zip
  if [[ ! -d "${WORLD_DIR}" ]]; then
    local EXTRACTED
    EXTRACTED="$(find "${DATA_DIR}" -maxdepth 1 -type d -name "*world*" | head -n1 || true)"
    [[ -n "${EXTRACTED}" ]] && mv "${EXTRACTED}" "${WORLD_DIR}"
  fi

  rm -f "${TMP_ZIP}"
  rm -f "${DATA_DIR}/reset-world.flag"

  log INFO "World installed successfully"
}

install_datapacks() {
  log INFO "Install datapacks"

  [[ "${DATAPACKS_ENABLED:-true}" == "true" ]] || {
    log INFO "Datapacks disabled"
    return
  }

  [[ -n "${DATAPACKS_S3_BUCKET:-}" ]] || {
    log INFO "DATAPACKS_S3_BUCKET not set, skipping datapacks"
    return
  }

  DATAPACKS_DIR="${DATA_DIR}/world/datapacks"
  mkdir -p "${DATAPACKS_DIR}"

  # now already datapacks present and sync once mode, skipping
  if [[ "${DATAPACKS_SYNC_ONCE}" == "true" ]] \
    && [[ -n "$(ls -A "${DATAPACKS_DIR}")" ]] \
    && [[ "${DATAPACKS_REMOVE_EXTRA}" != "true" ]]; then
    log INFO "Datapacks already present, skipping sync"
    return
  fi


  log INFO "Configuring MinIO client for datapacks"
  mc alias set s3 \
    "${S3_ENDPOINT}" \
    "${S3_ACCESS_KEY}" \
    "${S3_SECRET_KEY}" \
    || die "Failed to configure MinIO client"

  REMOVE_FLAG=""
  [[ "${DATAPACKS_REMOVE_EXTRA}" == "true" ]] && REMOVE_FLAG="--remove"

  log INFO "Syncing datapacks from s3://${DATAPACKS_S3_BUCKET}/${DATAPACKS_S3_PREFIX}"

  mc mirror \
    --overwrite \
    ${REMOVE_FLAG} \
    "s3/${DATAPACKS_S3_BUCKET}/${DATAPACKS_S3_PREFIX}" \
    "${DATAPACKS_DIR}" \
    || die "Failed to sync datapacks"

  log INFO "Datapacks installed successfully"
}

activate_datapacks() {
  local world_dir="${DATA_DIR}/world"

  [[ -d "$world_dir" ]] || {
    log INFO "World directory not found, skipping datapacks activation"
    return
  }

  activate_dir "/datapacks" "${world_dir}/datapacks" "datapacks"
}

install_resourcepacks() {
  log INFO "Install resourcepacks"

  [[ "${RESOURCEPACKS_ENABLED:-true}" == "true" ]] || {
    log INFO "Resourcepacks disabled"
    return
  }

  [[ -n "${RESOURCEPACKS_S3_BUCKET:-}" ]] || {
    log INFO "RESOURCEPACKS_S3_BUCKET not set, skipping resourcepacks"
    return
  }

  RP_DIR="${INPUT_RESOURCEPACKS_DIR}/resourcepacks"
  mkdir -p "${RP_DIR}"

  # now already resourcepacks present and sync once mode, skipping
  if [[ "${RESOURCEPACKS_SYNC_ONCE}" == "true" ]] \
   && find "${RP_DIR}" -mindepth 1 -maxdepth 1 -print -quit | grep -q . \
   && [[ "${RESOURCEPACKS_REMOVE_EXTRA}" != "true" ]]; then
  log INFO "Resourcepacks already present, skipping sync"
  return
  fi

  log INFO "Configuring MinIO client for resourcepacks"
  mc alias set s3 \
    "${S3_ENDPOINT}" \
    "${S3_ACCESS_KEY}" \
    "${S3_SECRET_KEY}" \
    || die "Failed to configure MinIO client"

  REMOVE_FLAG=""
  [[ "${RESOURCEPACKS_REMOVE_EXTRA}" == "true" ]] && REMOVE_FLAG="--remove"

  log INFO "Syncing resourcepacks from s3://${RESOURCEPACKS_S3_BUCKET}/${RESOURCEPACKS_S3_PREFIX}"
  mc mirror \
    --overwrite \
    ${REMOVE_FLAG} \
    "s3/${RESOURCEPACKS_S3_BUCKET}/${RESOURCEPACKS_S3_PREFIX}" \
    "${RP_DIR}" \
    || die "Failed to sync resourcepacks"
  
  # ---- server.properties linkage (optional) ----
  if [[ "${RESOURCEPACKS_AUTO_APPLY}" == "true" ]] && [[ -n "${RESOURCEPACK_URL:-}" ]] && [[ -f "${DATA_DIR}/server.properties" ]]; then
    log INFO "Applying resource-pack settings to server.properties"

    : "${RESOURCEPACK_SHA1:=}"

    sed -i \
      -e "s|^resource-pack=.*|resource-pack=${RESOURCEPACK_URL}|" \
      -e "s|^resource-pack-sha1=.*|resource-pack-sha1=${RESOURCEPACK_SHA1}|" \
      -e "s|^require-resource-pack=.*|require-resource-pack=${RESOURCEPACK_REQUIRED}|" \
      ${DATA_DIR}/server.properties || true
  fi

  if [[ "${RESOURCEPACKS_AUTO_APPLY}" == "true" ]] && [[ -n "${RESOURCEPACK_URL:-}" ]] && [[ ! -f "${DATA_DIR}/server.properties" ]]; then
    log WARN "server.properties not found, skipping resource-pack auto apply"
  fi

  log INFO "Resourcepacks installed successfully"
}

activate_resourcepacks() {
  activate_dir "${INPUT_RESOURCEPACKS_DIR:-/resourcepacks}" "${DATA_DIR}/resourcepacks" "resourcepacks"
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
    if grep -qE "^${PROP_KEY}=" "$props_file"; then
      sed -i "s|^${PROP_KEY}=.*|${PROP_KEY}=${ENV_VAL}|" "$props_file"
      log INFO "Updated property: ${PROP_KEY}=${ENV_VAL}"
    else
      echo "${PROP_KEY}=${ENV_VAL}" >> "$props_file"
      log INFO "Added property: ${PROP_KEY}=${ENV_VAL}"
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
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    echo "${key}=${value}" >> "$file"
  fi
}

apply_rcon_settings() {
  if [[ "${ENABLE_RCON}" == "true" ]]; then
    set_prop enable-rcon true
    set_prop rcon.port "${RCON_PORT:-25575}"

    if [[ -z "${RCON_PASSWORD}" ]]; then
      log ERROR "ENABLE_RCON=true but RCON_PASSWORD is empty"
      exit 1
    fi

    set_prop rcon.password "${RCON_PASSWORD}"
  else
    set_prop enable-rcon false
  fi
}

install_server_properties() {
  PROPS_FILE="${DATA_DIR}/server.properties"

  if [[ "${APPLY_SERVER_PROPERTIES_DIFF:-true}" == "true" ]]; then
    apply_server_properties_diff
  else
    log INFO "server.properties exists, no changes applied"
  fi

  apply_rcon_settings
}

# path to UUID cache file
UUID_CACHE_FILE="${DATA_DIR}/uuid_cache.json"  # select a suitable location

# create UUID cache file if not exists
init_uuid_cache() {
  [[ -f "$UUID_CACHE_FILE" ]] || echo "{}" > "$UUID_CACHE_FILE"
}

# get UUID for a given player name
uuid_for_player() {
  local name="$1"
  local cached
  local uuid

  init_uuid_cache

  cached=$(jq -r --arg n "$name" '.[$n] // empty' "$UUID_CACHE_FILE")
  if [[ -n "$cached" ]]; then
    echo "$cached"
    return 0
  fi

  uuid=$(curl -fsSL \
    "https://api.mojang.com/users/profiles/minecraft/${name}" \
    | jq -r '.id // empty') || return 1

  [[ -z "$uuid" ]] && return 1

  jq --arg n "$name" --arg u "$uuid" \
    '. + {($n): $u}' \
    "$UUID_CACHE_FILE" > "${UUID_CACHE_FILE}.tmp" \
    && mv "${UUID_CACHE_FILE}.tmp" "$UUID_CACHE_FILE"

  echo "$uuid"
}

# transform CSV string into newline-separated list
parse_csv() {
  echo "$1" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | sed '/^$/d'
}

# transform UUID into hyphenated form
uuid_with_hyphen() {
  local u="$1"
  # format: 8-4-4-4-12
  echo "${u:0:8}-${u:8:4}-${u:12:4}-${u:16:4}-${u:20:12}"
}

# function to generate ops.json
install_ops() {
  local FILE="${DATA_DIR}/ops.json"

  # now ops is empty
  [[ -z "${OPS_USERS:-}" ]] && return

  log INFO "Generating ops.json"

  {
    echo "["

    local first=true
    for name in $(parse_csv "${OPS_USERS}"); do
      # get UUID for a given player name
      uuid=$(uuid_for_player "$name") || continue
      [[ -z "$uuid" ]] && continue

      # first user skip comma
      [[ "$first" != true ]] && echo ","
      first=false

      # output ops.json entry
      cat <<EOF
  {
    "uuid": "$(uuid_with_hyphen "$uuid")",
    "name": "$name",
    "level": 4,
    "bypassesPlayerLimit": false
  }
EOF
    done
    echo "]"
  } > "$FILE"
}

# function to generate whitelist.json
install_whitelist() {
  local FILE="${DATA_DIR}/whitelist.json"

  # now whitelist disabled or empty
  [[ "${ENABLE_WHITELIST:-false}" != "true" ]] && return
  [[ -z "${WHITELIST_USERS:-}" ]] && return

  log INFO "Generating whitelist.json"

  {
    echo "["

    local first=true
    for name in $(parse_csv "${WHITELIST_USERS}"); do
      # get UUID for a given player name
      uuid=$(uuid_for_player "$name") || continue
      [[ -z "$uuid" ]] && continue

      # first user skip comma
      [[ "$first" != true ]] && echo ","
      first=false

      # output whitelist.json entry
      cat <<EOF
  {
    "uuid": "$(uuid_with_hyphen "$uuid")",
    "name": "$name"
  }
EOF
    done
    echo "]"
  } > "$FILE"
}

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
  # Expect mc available. Reuse common S3_* env.
  [[ -n "${S3_ENDPOINT:-}" ]] || die "S3_ENDPOINT is required for optimize mods"
  [[ -n "${S3_ACCESS_KEY:-}" ]] || die "S3_ACCESS_KEY is required for optimize mods"
  [[ -n "${S3_SECRET_KEY:-}" ]] || die "S3_SECRET_KEY is required for optimize mods"

  mc alias set s3 "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}" >/dev/null
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
          rm -f "$link"
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

detect_gpu() {
  log INFO "Detecting OpenCL GPU availability..."

  # ------------------------------------------------------------
  # 1. GPU device (Docker / WSL compatible)
  # ------------------------------------------------------------
  if [ ! -e /dev/nvidia0 ] && [ ! -e /dev/dxg ]; then
    log INFO "No NVIDIA GPU device found (/dev/nvidia* or /dev/dxg)"
    return 1
  fi
  log INFO "GPU device node found"

  # ------------------------------------------------------------
  # 2. OpenCL loader (path-based, not ldconfig)
  # ------------------------------------------------------------
  if ! ls /usr/lib*/libOpenCL.so* >/dev/null 2>&1; then
    log WARN "OpenCL loader (libOpenCL.so) not found"
    return 1
  fi
  log INFO "OpenCL loader present"

  # ------------------------------------------------------------
  # 3. clinfo existence
  # ------------------------------------------------------------
  if ! command -v clinfo >/dev/null 2>&1; then
    log WARN "clinfo not available"
    return 1
  fi

  # ------------------------------------------------------------
  # 4. clinfo sanity (minimal & fast)
  # ------------------------------------------------------------
  if ! clinfo --raw 2>/dev/null | grep -qi "NVIDIA"; then
    log WARN "OpenCL NVIDIA platform not detected"
    return 1
  fi

  log INFO "OpenCL GPU detected and usable"
  return 0
}

configure_c2me_opencl() {
    if ! has_c2me_mod; then
    return
  fi

  if [[ "${C2ME_OPENCL_FORCE:-auto}" == "true" ]]; then
    log WARN "C2ME OpenCL FORCE ENABLED"
    export C2ME_OPENCL_ENABLED=true
    return
  fi

  if detect_gpu; then
    export C2ME_OPENCL_ENABLED=true
    log INFO "C2ME OpenCL enabled (GPU mode)"
  else
    export C2ME_OPENCL_ENABLED=false
    log INFO "C2ME OpenCL disabled (CPU-safe mode)"
  fi
}

install() {
  log INFO "Install phase start"

  install_dirs
  install_eula
  cleaer_fabric_cache
  setup_server_icon

  configure_paper_configs
  generate_velocity_toml
  ensure_server_properties

  handle_reset_world_flag

  install_server        # server jar
  install_server_properties
  install_mods          # mods (most important)
  activate_mods         # activate mods
  install_datapacks     # datapacks
  activate_datapacks    # activate datapacks
  install_jvm_args
  install_c2me_jvm_args
  install_configs
  activate_configs
  apply_paper_global_from_env
  install_plugins
  activate_plugins
  if [[ ! "${TYPE}" == "velocity" ]]; then
    install_resourcepacks
    activate_resourcepacks
  fi
  install_whitelist
  install_ops
  configure_c2me_opencl

  log INFO "Install phase completed"
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

json_escape() {
  local s="$*"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

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

wait_for_server_exit() {
  local timeout="$1"
  local elapsed=0

  while [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; do
    if (( elapsed >= timeout )); then
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  return 0
}

rcon_say() {
  rcon_exec "say $*"
}

rcon_stop() {
  if [[ "${ENABLE_RCON}" != "true" ]]; then
    log INFO "RCON disabled, skipping rcon_stop"
    return 1
  fi

  local delay="${STOP_SERVER_ANNOUNCE_DELAY:-0}"
  local citizens_file="${DATA_DIR}/plugins/Citizens/saves.yml"

  if [[ -f "${citizens_file}" ]]; then
    log INFO "Citizens data detected: ${citizens_file}"
  else
    log INFO "Citizens data not found at shutdown: ${citizens_file}"
  fi

  if (( delay > 0 )); then
    rcon_tellraw_all "Server shutting down in ${delay} seconds." || true
    sleep "${delay}"
  else
    rcon_tellraw_all "Server shutting down now." || true
  fi

  log INFO "[shutdown] rcon: citizens save"
  if rcon_exec "citizens save"; then
    log INFO "[shutdown] rcon: citizens save succeeded"
  else
    log WARN "[shutdown] rcon: citizens save failed"
  fi

  log INFO "[shutdown] rcon: save-all"
  if rcon_exec "save-all"; then
    log INFO "[shutdown] rcon: save-all succeeded"
  else
    log WARN "[shutdown] rcon: save-all failed"
  fi

  log INFO "[shutdown] rcon: stop"
  if rcon_exec "stop"; then
    log INFO "[shutdown] rcon: stop succeeded"
  else
    log WARN "[shutdown] rcon: stop failed"
    return 1
  fi

  return 0
}

graceful_shutdown() {
  log INFO "[shutdown] begin"

  if ! rcon_stop_once; then
    log WARN "[shutdown] RCON stop failed or unavailable, sending TERM to server process"
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
      kill -TERM "${SERVER_PID}" 2>/dev/null || true
    fi
  fi

  log INFO "[shutdown] waiting for server process (timeout: ${SHUTDOWN_WAIT_TIMEOUT}s)"
  if wait_for_server_exit "${SHUTDOWN_WAIT_TIMEOUT}"; then
    log INFO "[shutdown] server process exited"
    log INFO "[shutdown] end"
    exit 0
  fi

  log WARN "[shutdown] timeout exceeded, sending TERM"
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill -TERM "${SERVER_PID}" 2>/dev/null || true
  fi

  if wait_for_server_exit "${SHUTDOWN_TERM_WAIT}"; then
    log INFO "[shutdown] server process exited after TERM"
    log INFO "[shutdown] end"
    exit 0
  fi

  log WARN "[shutdown] forcing kill"
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill -KILL "${SERVER_PID}" 2>/dev/null || true
  fi

  log INFO "[shutdown] end"
  exit 0
}

RCON_STOP_RESULT=1

# Put the lock on ephemeral filesystem (NOT on /data / PVC)
RCON_STOP_LOCK="${RCON_STOP_LOCK:-/tmp/.rcon-stop.lockdir}"
RCON_STOP_IN_PROGRESS=0
SERVER_PID=""

cleanup_rcon_lock_on_boot() {
  # Remove stale lock from previous container runs (best-effort)
  rm -rf "${RCON_STOP_LOCK}" 2>/dev/null || true
}

acquire_rcon_stop_lock() {
  mkdir "${RCON_STOP_LOCK}" 2>/dev/null
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

rcon_stop_once() {
  # Prevent re-entrance within same process
  if [ "${RCON_STOP_IN_PROGRESS}" = "1" ]; then
    return "${RCON_STOP_RESULT}"
  fi

  # Prevent double execution across preStop/trap (but allow first run)
  if ! acquire_rcon_stop_lock; then
    log INFO "rcon_stop already running (lock exists), skipping"
    return "${RCON_STOP_RESULT}"
  fi

  # Mark as in-progress ONLY after acquiring the lock
  RCON_STOP_IN_PROGRESS=1


  # Best-effort: force a final save before stopping the server
  # Prefer "save-all flush" (waits for flush). If unsupported, fall back to "save-all".
  if ! rcon_exec "save-all flush"; then
    log WARN "save-all flush failed; trying save-all"
    rcon_exec "save-all" || true
  fi
  rcon_stop || true
}

# Single source of truth for signals (make sure there is only ONE trap)
trap 'graceful_shutdown' TERM INT QUIT

run_server() {
  cleanup_rcon_lock_on_boot

  "$@" &
  SERVER_PID=$!

  wait "$SERVER_PID"
}

# ==========================================================
# Runtime
# ==========================================================
runtime() {
  log INFO "Starting runtime (TYPE=${TYPE})"

  case "${TYPE}" in
    fabric)
      log INFO "Launching Fabric server (single JVM)"
      run_server java @"${JVM_ARGS_FILE}" \
        -jar "${DATA_DIR}/fabric-server-launch.jar" nogui
      ;;

    quilt|paper|purpur|mohist|taiyitist|youer|vanilla)
      log INFO "Launching ${TYPE} server (single JVM)"
      run_server java @"${JVM_ARGS_FILE}" \
        -jar "${DATA_DIR}/server.jar" nogui
      ;;

    forge|neoforge)
      cd "${DATA_DIR}"
      [[ -x "./run.sh" ]] || die "NeoForge runtime not installed (run.sh missing)"
      chmod +x ./run.sh

      log INFO "Launching ${TYPE} server"
      run_server ./run.sh nogui
      ;;

    velocity)
      log INFO "Launching Velocity proxy"
      run_server java @"${JVM_ARGS_FILE}" \
        -jar "${DATA_DIR}/velocity.jar"
      ;;

    *)
      die "Unknown TYPE: ${TYPE}"
      ;;
  esac
}

case "$1" in
  rcon)
    shift
    rcon_exec "$@"
    exit $?
    ;;
  rcon-say)
    shift
    rcon_say "$@"
    exit $?
    ;;
  rcon-stop)
    rcon_stop_once
    exit 0
    ;;
esac

main() {
  log INFO "Minecraft Runtime Booting..."
  preflight
  detect_runtime_env
  install
  runtime
}

if [[ "${__SOURCED:-0}" != "1" ]]; then
  main "$@"
fi
