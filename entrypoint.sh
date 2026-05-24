#!/usr/bin/env bash
set -Eeuo pipefail

ENTRYPOINT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/lib/logging.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/logging.sh"
# shellcheck source=scripts/lib/filesystem.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/filesystem.sh"
# shellcheck source=scripts/lib/runtime.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/runtime.sh"
# shellcheck source=scripts/lib/lifecycle.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/lifecycle.sh"
# shellcheck source=scripts/lib/rcon.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/rcon.sh"
# shellcheck source=scripts/lib/shutdown.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/shutdown.sh"
# shellcheck source=scripts/lib/s3_client.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/s3_client.sh"
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

preflight() {
  log INFO "Preflight checks..."

  [[ -d "${DATA_DIR}" ]] || die "${DATA_DIR} does not exist"
  touch "${DATA_DIR}/.write_test" 2>/dev/null || die "${DATA_DIR} is not writable"
  safe_rm_f "${DATA_DIR}/.write_test"

  [[ -n "${EULA:-}" ]] || die "EULA is not set"

  if ! is_auto_type "${TYPE:-vanilla}" && ! is_supported_runtime_type "${TYPE:-vanilla}"; then
    die "Invalid TYPE: ${TYPE}"
  fi

  if [[ "${TYPE:-vanilla}" != "vanilla" && "${TYPE:-vanilla}" != "auto" && -z "${VERSION:-}" ]]; then
    die "VERSION must be set when TYPE is not vanilla"
  fi

  if [[ "${ENABLE_RCON}" == "true" ]]; then
    [[ -n "${RCON_PASSWORD:-}" ]] || die "ENABLE_RCON=true but RCON_PASSWORD is empty"
    [[ "${RCON_PASSWORD}" != "changeme" ]] || die "RCON_PASSWORD=changeme is not allowed"
  fi

  safe_rm_f "${DATA_DIR}/.ready"
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

  JAVA_VERSION_RAW="$(java -version 2>&1 | head -n 1 || true)"
  JAVA_MAJOR="$(
    java -XshowSettings:properties -version 2>&1 \
      | awk -F= '/java.specification.version/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' \
      | sed 's/^1\.//'
  )"
  [[ -n "${JAVA_MAJOR}" ]] || JAVA_MAJOR="unknown"

  RUNTIME_ARCH_NORM="$(uname -m)"
  case "${RUNTIME_ARCH_NORM}" in
    amd64) RUNTIME_ARCH_NORM="x86_64" ;;
    aarch64|arm64) RUNTIME_ARCH_NORM="arm64" ;;
  esac

  if [[ -f /.dockerenv || -f /run/.containerenv || -n "${container:-}" ]]; then
    RUNTIME_CONTAINER="true"
  else
    RUNTIME_CONTAINER="false"
  fi

  if [[ -e /dev/nvidia0 || -e /dev/dxg || -d /dev/dri ]]; then
    RUNTIME_GPU="present"
  else
    RUNTIME_GPU="none"
  fi

  export RUNTIME_OS RUNTIME_OS_VERSION JAVA_VERSION_RAW JAVA_MAJOR RUNTIME_ARCH_NORM RUNTIME_CONTAINER RUNTIME_GPU
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
    "${DATA_DIR}/logs" \
    "${DATA_DIR}/config" \
    "${DATA_DIR}/world"

  if [[ "${TYPE}" == "paper" || "${TYPE}" == "purpur" || "${TYPE}" == "spigot" ]]; then
    mkdir -p "${DATA_DIR}/plugins"
  fi

  if [[ "${TYPE}" == "fabric" || "${TYPE}" == "forge" || "${TYPE}" == "neoforge" ]]; then
    mkdir -p "${INPUT_MODS_DIR}"
  fi

  # Permissions check
  touch "${DATA_DIR}/logs/.perm_test" 2>/dev/null || die "${DATA_DIR}/logs is not writable"
  safe_rm_f "${DATA_DIR}/logs/.perm_test"

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

  if ! find "$src" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    log INFO "${name} directory is empty (${src}), skipping activation"
    return
  fi

  local parent
  parent="$(dirname "$dst")"
  local base
  base="$(basename "$dst")"

  local staging backup
  staging="$(mktemp -d "${parent}/.${base}.staging.XXXXXX")"
  backup="$(mktemp -d "${parent}/.${base}.old.XXXXXX")"
  safe_rm_rf "$backup"

  log INFO "Activating ${name} (atomic) (${src} -> ${dst})"

  # 1. sync into staging (delete OK here)
  if ! rsync -a --delete "$src"/ "$staging"/; then
    safe_rm_rf "$staging"
    return 1
  fi

  # 2. atomic switch
  if [[ -d "$dst" ]]; then
    if ! safe_mv "$dst" "$backup"; then
      safe_rm_rf "$staging"
      return 1
    fi
  fi

  if ! safe_mv "$staging" "$dst"; then
    [[ ! -d "$backup" ]] || safe_mv "$backup" "$dst" || true
    safe_rm_rf "$staging"
    return 1
  fi

  # 3. cleanup backup
  safe_rm_rf "$backup"
}

install_eula() {
  log INFO "Handling EULA"

  case "${EULA}" in
    true)
      echo "eula=true" > "${DATA_DIR}/eula.txt"
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
    safe_rm_f "${icon_path}"
    return 1
  fi

  log INFO "Server icon installed: ${icon_path}"
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
    local sed_value
    sed_value="$(escape_sed_replacement "$value")"
    sed -i -E "s|^[[:space:]]*(${key})[[:space:]]*=.*$|\1=${sed_value}|g" "$file"
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
  [[ "${TYPE:-}" == "paper" ]] || return 0

  local cfg_dir="${PAPER_CONFIG_DIR:-${DATA_DIR}/config}"
  mkdir -p "$cfg_dir"

  if is_true "${PAPER_VELOCITY:-false}"; then
    local secret="${PAPER_VELOCITY_SECRET:-${VELOCITY_SECRET:-}}"
    [[ -n "$secret" ]] || die "PAPER_VELOCITY=true but no PAPER_VELOCITY_SECRET or VELOCITY_SECRET"

    if command -v yq >/dev/null 2>&1; then
      # Always write these; yq_set_yaml assumes touch/creation
      yq_set_yaml "${cfg_dir}/paper-global.yml" "proxies.velocity.enabled" "true"
      yq_set_yaml "${cfg_dir}/paper-global.yml" "proxies.velocity.secret" "$secret"

      # Do the same for legacy setups (regardless of file presence)
      yq_set_yaml "${cfg_dir}/paper.yml" "settings.velocity-support.enabled" "true"
      yq_set_yaml "${cfg_dir}/paper.yml" "settings.velocity-support.secret" "$secret"

      yq_set_yaml "${cfg_dir}/spigot.yml" "settings.bungeecord" "true"
    else
      log WARN "yq not found; paper-global.yml will use minimal fallback and legacy Paper files are skipped"
    fi
  fi

  if [[ -n "${PAPER_CONFIG_OVERRIDES:-}" ]]; then
    require_yq
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
  configure_mc_alias "mods"

  local -a remove_args=()
  if [[ "${MODS_REMOVE_EXTRA}" == "true" ]]; then
    remove_args=(--remove)
    ensure_s3_source_nonempty_for_remove "s3/${MODS_S3_BUCKET}/${MODS_S3_PREFIX}" "mods"
  fi

  log INFO "Syncing mods from s3://${MODS_S3_BUCKET}/${MODS_S3_PREFIX}"

  mc mirror \
    --overwrite \
    "${remove_args[@]}" \
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
  configure_mc_alias "configs"


  local -a remove_args=()
  if [[ "${CONFIGS_REMOVE_EXTRA}" == "true" ]]; then
    remove_args=(--remove)
    ensure_s3_source_nonempty_for_remove "s3/${CONFIGS_S3_BUCKET}/${CONFIGS_S3_PREFIX}" "configs"
  fi

  log INFO "Syncing configs from s3://${CONFIGS_S3_BUCKET}/${CONFIGS_S3_PREFIX}"

  mc mirror \
    --overwrite \
    "${remove_args[@]}" \
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
  [[ "${TYPE:-}" == "paper" ]] || return 0
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
    && [[ "${TYPE:-auto}" != "spigot" ]] \
    && [[ "${TYPE:-auto}" != "spigot" ]] \
    && [[ "${TYPE:-auto}" != "spigot" ]] \
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

  # shellcheck disable=SC2317,SC2329  # Called indirectly via RETURN trap in plugin sync flow.
  cleanup_plugins_tmp() {
    [[ -z "${tmp_remote:-}" ]] || safe_rm_f "${tmp_remote}" 2>/dev/null || true
    [[ -z "${tmp_remote_jars:-}" ]] || safe_rm_f "${tmp_remote_jars}" 2>/dev/null || true
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
  configure_mc_alias "plugins"

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

  # shellcheck disable=SC2317,SC2329  # Called indirectly via RETURN trap in plugin sync flow.
  cleanup_plugins_tmp() {
    [[ -z "${tmp_remote:-}" ]] || safe_rm_f "${tmp_remote}" 2>/dev/null || true
    [[ -z "${tmp_remote_topjars:-}" ]] || safe_rm_f "${tmp_remote_topjars}" 2>/dev/null || true
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

  if [[ "${PLUGINS_REMOVE_EXTRA:-false}" == "true" ]] && [[ ! -s "${tmp_remote_topjars}" ]]; then
    die "PLUGINS_REMOVE_EXTRA=true but remote plugins prefix has no top-level .jar files; refusing to remove local plugins"
  fi

  # -----------------------------------
  # Download loop (top-level jars only)
  # -----------------------------------
  local obj rel dest
  local errors=0

  while IFS= read -r obj; do
    [[ -n "${obj}" ]] || continue

    # Defensive: skip directory-like entries
    [[ "${obj}" != */ ]] || continue

    rel="${obj#"${src}"}"
    [[ "${rel}" != "${obj}" ]] || continue
    [[ -n "${rel}" ]] || continue

    # Only sync top-level jars
    if [[ "${rel}" != *.jar || "${rel}" == */* ]]; then
      continue
    fi

    dest="${plugins_dir}/${rel}"
    safe_rm_f "${dest}" || true
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
          safe_rm_f "${local_jar}" || {
            [[ "${strict}" == "true" ]] && die "Failed to remove extra jar: ${local_jar}"
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
  log INFO "Install plugins (Paper | Purpur | Mohist | Taiyitist | Youer | Velocity only)"

  [[ "${PLUGINS_ENABLED:-true}" == "true" ]] || { log INFO "Plugins disabled"; return 0; }

  if [[ "${TYPE:-auto}" != "paper" ]] \
    && [[ "${TYPE:-auto}" != "spigot" ]] \
    && [[ "${TYPE:-auto}" != "spigot" ]] \
    && [[ "${TYPE:-auto}" != "purpur" ]] \
    && [[ "${TYPE:-auto}" != "mohist" ]] \
    && [[ "${TYPE:-auto}" != "taiyitist" ]] \
    && [[ "${TYPE:-auto}" != "youer" ]] \
    && [[ "${TYPE:-auto}" != "velocity" ]]; then
    log INFO "TYPE=${TYPE}, skipping plugins"
    return 0
  fi

  local src="/plugins"
  local dst="${DATA_DIR}/plugins"

  [[ -d "${src}" ]] || {
    log INFO "No plugins input directory found (${src}), skipping"
    return 0
  }

  if ! find "${src}" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    log INFO "Plugins input directory is empty (${src}), skipping activation"
    return 0
  fi

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
      local tmp
      tmp="$(mktemp "${td}/.$(basename "${t}").tmp.XXXXXX")" || { errors=$((errors+1)); log WARN "Failed to create temp jar: ${t}"; continue; }
      cp -a "${s}" "${tmp}" || { safe_rm_f "${tmp}"; errors=$((errors+1)); log WARN "Failed to copy jar: ${s}"; continue; }
      safe_mv_f "${tmp}" "${t}" || { safe_rm_f "${tmp}"; errors=$((errors+1)); log WARN "Failed to move jar into place: ${t}"; continue; }
    else
      # non-jar: seed only (never overwrite)
      if [[ -e "${t}" ]]; then
        continue
      fi
      local tmp
      tmp="$(mktemp "${td}/.$(basename "${t}").tmp.XXXXXX")" || { errors=$((errors+1)); log WARN "Failed to create temp non-jar: ${t}"; continue; }
      cp -a "${s}" "${tmp}" || { safe_rm_f "${tmp}"; errors=$((errors+1)); log WARN "Failed to seed non-jar: ${s}"; continue; }
      safe_mv_f "${tmp}" "${t}" || { safe_rm_f "${tmp}"; errors=$((errors+1)); log WARN "Failed to move non-jar into place: ${t}"; continue; }
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
        local rel="${local_jar#"${dst}"/}"
        if [[ "${rel}" == */* ]]; then
          continue
        fi
        if ! grep -Fxq "${rel}" "${tmp_src_jars}"; then
          log INFO "Removing extra jar from ${dst}: ${rel}"
          safe_rm_f "${local_jar}" || log WARN "Failed to remove extra jar: ${local_jar}"
        fi
      done < <(find "${dst}" -maxdepth 1 -type f -name "*.jar" -print0)

      safe_rm_f "${tmp_src_jars}"
    fi

    log INFO "activate_plugins completed (non-jar protected)"
  fi

  return 0
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
  configure_mc_alias "datapacks"

  local -a remove_args=()
  if [[ "${DATAPACKS_REMOVE_EXTRA}" == "true" ]]; then
    remove_args=(--remove)
    ensure_s3_source_nonempty_for_remove "s3/${DATAPACKS_S3_BUCKET}/${DATAPACKS_S3_PREFIX}" "datapacks"
  fi

  log INFO "Syncing datapacks from s3://${DATAPACKS_S3_BUCKET}/${DATAPACKS_S3_PREFIX}"

  mc mirror \
    --overwrite \
    "${remove_args[@]}" \
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
  configure_mc_alias "resourcepacks"

  local -a remove_args=()
  if [[ "${RESOURCEPACKS_REMOVE_EXTRA}" == "true" ]]; then
    remove_args=(--remove)
    ensure_s3_source_nonempty_for_remove "s3/${RESOURCEPACKS_S3_BUCKET}/${RESOURCEPACKS_S3_PREFIX}" "resourcepacks"
  fi

  log INFO "Syncing resourcepacks from s3://${RESOURCEPACKS_S3_BUCKET}/${RESOURCEPACKS_S3_PREFIX}"
  mc mirror \
    --overwrite \
    "${remove_args[@]}" \
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
      "${DATA_DIR}/server.properties" || true
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

  if [[ "${APPLY_SERVER_PROPERTIES_DIFF:-true}" == "true" ]]; then
    apply_server_properties_diff
  else
    log INFO "server.properties exists, no changes applied"
  fi

  apply_rcon_settings
}

# path to UUID cache file
UUID_CACHE_FILE="${DATA_DIR}/uuid_cache.json"  # select a suitable location

# create UUID cache file if not exists, and fail fast if it is not a JSON object
init_uuid_cache() {
  if [[ ! -f "$UUID_CACHE_FILE" ]]; then
    echo "{}" > "$UUID_CACHE_FILE"
    return 0
  fi

  if ! jq -e 'type == "object"' "$UUID_CACHE_FILE" >/dev/null 2>&1; then
    die "Invalid UUID cache at ${UUID_CACHE_FILE}; expected a JSON object. Fix or remove the file to regenerate it."
  fi
}

# get UUID for a given player name
uuid_for_player() {
  local name="$1"
  local cached
  local tmp
  local uuid

  init_uuid_cache

  cached=$(jq -r --arg n "$name" '.[$n] // empty' "$UUID_CACHE_FILE")
  if [[ -n "$cached" ]]; then
    [[ "$cached" =~ ^[0-9a-fA-F]{32}$ ]] || die "Invalid cached UUID for player '${name}'"
    echo "$cached"
    return 0
  fi

  uuid=$(curl -fsSL \
    "https://api.mojang.com/users/profiles/minecraft/${name}" \
    | jq -r '.id // empty') || return 1

  [[ -z "$uuid" ]] && return 1
  [[ "$uuid" =~ ^[0-9a-fA-F]{32}$ ]] || die "Invalid UUID returned for player '${name}'"

  tmp="$(mktemp "${UUID_CACHE_FILE}.tmp.XXXXXX")" || return 1
  if ! jq --arg n "$name" --arg u "$uuid" \
    '. + {($n): $u}' \
    "$UUID_CACHE_FILE" > "$tmp"; then
    safe_rm_f "$tmp"
    return 1
  fi
  if ! safe_mv_f "$tmp" "$UUID_CACHE_FILE"; then
    safe_rm_f "$tmp"
    return 1
  fi

  echo "$uuid"
}

# transform CSV string into newline-separated list
# NOTE: this is meant to feed `while IFS= read -r ...` iteration. The main
#       hazard being avoided is `for name in $(parse_csv ...)`, where command
#       substitution plus `for ... in` triggers word splitting and globbing and
#       corrupts values containing spaces or glob characters. That issue is
#       independent of `set -u`. Prefer:
#         while IFS= read -r name; do ...; done < <(parse_csv "${CSV}")
#       This is a simple comma-separated env-var parser: it trims leading and
#       trailing whitespace and drops empty items. Embedded commas are not
#       supported.
parse_csv() {
  if [[ -z "${1:-}" ]]; then
    return 0
  fi
  printf '%s' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d'
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
  local tmp
  local uuid

  # now ops is empty
  [[ -z "${OPS_USERS:-}" ]] && return

  log INFO "Generating ops.json"
  init_uuid_cache
  tmp="$(mktemp "${FILE}.tmp.XXXXXX")"

  if ! {
    while IFS= read -r name; do
      uuid=$(uuid_for_player "$name") || continue

      jq -nc \
        --arg uuid "$(uuid_with_hyphen "$uuid")" \
        --arg name "$name" \
        --argjson level 4 \
        --argjson bypassesPlayerLimit false \
        '{uuid:$uuid,name:$name,level:$level,bypassesPlayerLimit:$bypassesPlayerLimit}'
    done < <(parse_csv "${OPS_USERS}")
  } | jq -s '.' > "$tmp"; then
    safe_rm_f "$tmp"
    return 1
  fi

  if ! safe_mv_f "$tmp" "$FILE"; then
    safe_rm_f "$tmp"
    return 1
  fi
}

# function to generate whitelist.json
install_whitelist() {
  local FILE="${DATA_DIR}/whitelist.json"
  local tmp
  local uuid

  # now whitelist disabled or empty
  [[ "${ENABLE_WHITELIST:-false}" != "true" ]] && return
  [[ -z "${WHITELIST_USERS:-}" ]] && return

  log INFO "Generating whitelist.json"
  init_uuid_cache
  tmp="$(mktemp "${FILE}.tmp.XXXXXX")"

  if ! {
    while IFS= read -r name; do
      uuid=$(uuid_for_player "$name") || continue

      jq -nc \
        --arg uuid "$(uuid_with_hyphen "$uuid")" \
        --arg name "$name" \
        '{uuid:$uuid,name:$name}'
    done < <(parse_csv "${WHITELIST_USERS}")
  } | jq -s '.' > "$tmp"; then
    safe_rm_f "$tmp"
    return 1
  fi

  if ! safe_mv_f "$tmp" "$FILE"; then
    safe_rm_f "$tmp"
    return 1
  fi
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
  if ! find /usr/lib /usr/local/lib -path '*libOpenCL.so*' -print -quit 2>/dev/null | grep -q .; then
    log WARN "OpenCL loader (libOpenCL.so) not found"
    return 1
  fi
  log INFO "OpenCL loader present"

  # ------------------------------------------------------------
  # 3. clinfo is diagnostic only; containerized OpenCL can work
  #    even when clinfo is missing or unreliable.
  # ------------------------------------------------------------
  if ! command -v clinfo >/dev/null 2>&1; then
    log WARN "clinfo not available; continuing with device + loader detection"
    return 0
  fi

  if ! clinfo --raw 2>/dev/null | grep -qi "NVIDIA"; then
    log WARN "clinfo did not report NVIDIA; continuing because clinfo is not authoritative"
    return 0
  fi

  log INFO "OpenCL GPU detected"
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

extract_mrpack_index() {
  local archive="$1"
  local out="$2"

  [[ -f "$archive" ]] || die "mrpack archive not found: ${archive}"

  case "$out" in
    "${DATA_DIR}"|"${DATA_DIR}"/*)
      die "Refusing to write mrpack index under DATA_DIR: ${out}"
      ;;
  esac

  command -v unzip >/dev/null 2>&1 || die "unzip is required to read mrpack archives"

  if ! unzip -p "$archive" modrinth.index.json > "$out"; then
    die "modrinth.index.json not found in mrpack archive: ${archive}"
  fi

  [[ -s "$out" ]] || die "modrinth.index.json is empty: ${archive}"
  jq -e . "$out" >/dev/null || die "modrinth.index.json is not valid JSON: ${archive}"
}

validate_modrinth_index() {
  local index="$1"

  [[ -f "$index" ]] || die "Modrinth index not found: ${index}"

  jq -e '
    type == "object"
    and (.formatVersion | type == "number")
    and .game == "minecraft"
    and (.versionId | type == "string")
    and (.files | type == "array")
    and ((has("dependencies") | not) or (.dependencies | type == "object"))
    and (.files | all(.[];
      type == "object"
      and (.path | type == "string")
      and (.downloads | type == "array" and length > 0 and all(.[]; type == "string" and test("^[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+$")))
      and (.hashes | type == "object")
      and (.hashes.sha1 | type == "string")
      and (.hashes.sha512 | type == "string")
      and ((has("env") | not) or (.env | type == "object"))
      and (if has("env") and (.env | has("server")) then
        (.env.server == "required" or .env.server == "optional" or .env.server == "unsupported")
      else true end)
      and (if has("env") and (.env | has("client")) then
        (.env.client == "required" or .env.client == "optional" or .env.client == "unsupported")
      else true end)
    ))
  ' "$index" >/dev/null || die "Invalid Modrinth index schema: ${index}"
}

safe_modpack_path() {
  local path="$1"
  local kind="${2:-file}"
  local part
  local -a parts

  [[ -n "$path" ]] || die "Unsafe ${kind} path: empty"
  [[ "$path" != /* ]] || die "Unsafe ${kind} path: absolute path: ${path}"
  [[ ! "$path" =~ ^[A-Za-z]: ]] || die "Unsafe ${kind} path: Windows drive path: ${path}"
  [[ "$path" != *\\* ]] || die "Unsafe ${kind} path: backslash is not allowed: ${path}"

  if printf '%s' "$path" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    die "Unsafe ${kind} path: control character is not allowed"
  fi

  IFS='/' read -r -a parts <<< "$path"
  for part in "${parts[@]}"; do
    [[ "$part" != ".." ]] || die "Unsafe ${kind} path: parent traversal: ${path}"
    [[ -n "$part" ]] || die "Unsafe ${kind} path: empty path segment: ${path}"
  done

  case "$path" in
    world|world/*|saves|saves/*|logs|logs/*|.minecraft|.minecraft/*|\
    .server-install.json|.modpack-install.json|server.properties|eula.txt|ops.json|whitelist.json)
      die "Unsafe ${kind} path: reserved path: ${path}"
      ;;
  esac

  case "$path" in
    mods/*|config/*|defaultconfigs/*|datapacks/*|resourcepacks/*)
      return 0
      ;;
    *)
      die "Unsafe ${kind} path: outside allowed modpack paths: ${path}"
      ;;
  esac
}

select_modrinth_server_files() {
  local index="$1"
  local file path

  [[ -f "$index" ]] || die "Modrinth index not found: ${index}"

  jq -c '.files[] | select((.env.server? // "required") == "required")' "$index" |
    while IFS= read -r file; do
      path="$(jq -er '.path' <<< "$file")" || die "Selected Modrinth file is missing path"
      safe_modpack_path "$path" file
      printf '%s\n' "$file"
    done
}

modpack_install_marker() {
  printf '%s/.modpack-install.json' "${DATA_DIR}"
}

modpack_file_hash_matches() {
  local file="$1"
  local sha1="$2"
  local sha512="$3"

  [[ -f "$file" ]] || return 1
  echo "${sha512}  ${file}" | sha512sum -c - >/dev/null 2>&1 || return 1
  echo "${sha1}  ${file}" | sha1sum -c - >/dev/null 2>&1 || return 1
}

modpack_marker_has_file() {
  local relpath="$1"
  local marker
  marker="$(modpack_install_marker)"

  [[ -f "$marker" ]] || return 1
  jq -e 'type == "object" and .schemaVersion == 1 and (.files | type == "array")' "$marker" >/dev/null \
    || die "Invalid modpack install marker: ${marker}"
  jq -e --arg path "$relpath" '.files[]? | select(.path == $path)' "$marker" >/dev/null
}

download_modpack_file() {
  local url="$1"
  local out="$2"
  local label="$3"
  local src

  case "$url" in
    file://*)
      is_true "${MODPACK_ALLOW_FILE_URL:-false}" || die "file:// modpack downloads require MODPACK_ALLOW_FILE_URL=true"
      src="${url#file://}"
      [[ -f "$src" ]] || die "Local modpack source not found for ${label}"
      cp "$src" "$out" || die "Failed to copy local modpack source for ${label}"
      ;;
    https://*)
      die "HTTPS modpack downloads are not implemented in this phase"
      ;;
    *)
      die "Unsupported modpack download URL for ${label}"
      ;;
  esac

  [[ -s "$out" ]] || die "Downloaded modpack file is empty for ${label}"
}

verify_modpack_file() {
  local file="$1"
  local sha1="$2"
  local sha512="$3"
  local label="$4"

  echo "${sha512}  ${file}" | sha512sum -c - >/dev/null || die "SHA512 mismatch for modpack file: ${label}"
  echo "${sha1}  ${file}" | sha1sum -c - >/dev/null || die "SHA1 mismatch for modpack file: ${label}"
}

install_modpack_file() {
  local relpath="$1"
  local src="$2"
  local sha1="$3"
  local sha512="$4"
  local target parent tmp

  safe_modpack_path "$relpath" file
  target="${DATA_DIR}/${relpath}"
  parent="$(dirname "$target")"

  case "$target" in
    "${DATA_DIR}"/*) ;;
    *) die "Refusing to install modpack file outside DATA_DIR: ${relpath}" ;;
  esac

  if [[ -e "$target" ]]; then
    if modpack_file_hash_matches "$target" "$sha1" "$sha512"; then
      log INFO "Modpack file already present with expected hash: ${relpath}"
      return 0
    fi

    if modpack_marker_has_file "$relpath"; then
      log INFO "Replacing previously managed modpack file: ${relpath}"
    elif [[ "$relpath" == *.jar ]]; then
      die "Refusing to overwrite user-owned jar from modpack: ${relpath}"
    else
      log INFO "Skipping existing user-owned modpack seed file: ${relpath}"
      return 2
    fi
  fi

  mkdir -p "$parent"
  tmp="$(mktemp "${parent}/.$(basename "$target").tmp.XXXXXX")"
  cp "$src" "$tmp" || {
    safe_rm_f "$tmp"
    die "Failed to stage modpack file: ${relpath}"
  }
  if ! safe_mv_f "$tmp" "$target"; then
    safe_rm_f "$tmp"
    return 1
  fi
}

write_modpack_marker() {
  local marker="$1"
  local tmp_files="$2"
  local source_url="$3"
  local version_id="$4"
  local index_sha512="$5"
  local tmp

  tmp="$(mktemp "${marker}.tmp.XXXXXX")"
  if ! jq -n \
    --arg sourceUrl "$source_url" \
    --arg versionId "$version_id" \
    --arg indexSha512 "$index_sha512" \
    --arg installedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --slurpfile files "$tmp_files" \
    '{
      schemaVersion: 1,
      format: "mrpack",
      sourceUrl: $sourceUrl,
      versionId: $versionId,
      indexSha512: $indexSha512,
      installMode: "server",
      files: $files[0],
      overrides: [],
      installedAt: $installedAt
    }' > "$tmp"; then
    safe_rm_f "$tmp"
    return 1
  fi
  if ! safe_mv_f "$tmp" "$marker"; then
    safe_rm_f "$tmp"
    return 1
  fi
}

modpack_marker_matches() {
  local marker="$1"
  local source_url="$2"
  local version_id="$3"
  local index_sha512="$4"
  local relpath sha1 sha512

  [[ -f "$marker" ]] || return 1
  jq -e 'type == "object" and .schemaVersion == 1 and (.files | type == "array")' "$marker" >/dev/null \
    || die "Invalid modpack install marker: ${marker}"

  jq -e \
    --arg sourceUrl "$source_url" \
    --arg versionId "$version_id" \
    --arg indexSha512 "$index_sha512" \
    '.format == "mrpack"
      and .sourceUrl == $sourceUrl
      and .versionId == $versionId
      and .indexSha512 == $indexSha512
      and .installMode == "server"' "$marker" >/dev/null || return 1

  while IFS=$'\t' read -r relpath sha1 sha512; do
    [[ -n "$relpath" ]] || continue
    safe_modpack_path "$relpath" file
    modpack_file_hash_matches "${DATA_DIR}/${relpath}" "$sha1" "$sha512" || return 1
  done < <(jq -r '.files[] | [.path, .sha1, .sha512] | @tsv' "$marker")
}

install_modrinth_mrpack() {
  local archive="$1"
  local source_url="$2"
  local tmpdir index selected tmp_files marker version_id index_sha512
  local file relpath url sha1 sha512 downloaded

  tmpdir="$(mktemp -d)"
  index="${tmpdir}/modrinth.index.json"
  selected="${tmpdir}/selected.jsonl"
  tmp_files="${tmpdir}/files.json"
  marker="$(modpack_install_marker)"

  extract_mrpack_index "$archive" "$index"
  validate_modrinth_index "$index"
  version_id="$(jq -er '.versionId' "$index")"
  index_sha512="$(sha512sum "$index")"
  index_sha512="${index_sha512%% *}"

  if ! is_true "${MODPACK_FORCE_REINSTALL:-false}" \
    && modpack_marker_matches "$marker" "$source_url" "$version_id" "$index_sha512"; then
    log INFO "Modpack marker matches; skipping modpack install"
    safe_rm_rf "$tmpdir"
    return 0
  fi

  select_modrinth_server_files "$index" > "$selected"
  : > "$tmp_files"

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    relpath="$(jq -er '.path' <<< "$file")"
    url="$(jq -er '.downloads[0]' <<< "$file")"
    sha1="$(jq -er '.hashes.sha1' <<< "$file")"
    sha512="$(jq -er '.hashes.sha512' <<< "$file")"
    downloaded="$(mktemp "${tmpdir}/downloaded-$(basename "$relpath").XXXXXX")"

    download_modpack_file "$url" "$downloaded" "$relpath"
    verify_modpack_file "$downloaded" "$sha1" "$sha512" "$relpath"
    if install_modpack_file "$relpath" "$downloaded" "$sha1" "$sha512"; then
      jq -nc --arg path "$relpath" --arg sha1 "$sha1" --arg sha512 "$sha512" \
        '{path:$path,sha1:$sha1,sha512:$sha512}' >> "$tmp_files"
    else
      local status=$?
      if [[ "$status" -ne 2 ]]; then
        safe_rm_rf "$tmpdir"
        return "$status"
      fi
    fi
  done < "$selected"

  if ! jq -s '.' "$tmp_files" > "${tmp_files}.array"; then
    safe_rm_rf "$tmpdir"
    return 1
  fi
  if ! write_modpack_marker "$marker" "${tmp_files}.array" "$source_url" "$version_id" "$index_sha512"; then
    safe_rm_rf "$tmpdir"
    return 1
  fi
  safe_rm_rf "$tmpdir"
  log INFO "Modpack install completed: ${version_id}"
}

install_modpack() {
  local format tmpdir archive source

  [[ -n "${MODPACK_URL:-}" ]] || return 0

  [[ "${MODPACK_INSTALL_MODE}" == "server" ]] || die "Only MODPACK_INSTALL_MODE=server is supported in this phase"
  [[ "${MODPACK_FORMAT}" == "auto" || "${MODPACK_FORMAT}" == "mrpack" ]] || die "Only MODPACK_FORMAT=auto or mrpack is supported"
  is_true "${MODPACK_REMOVE_EXTRA:-false}" && die "MODPACK_REMOVE_EXTRA=true is not supported in this phase"
  is_true "${MODPACK_INCLUDE_OPTIONAL:-false}" && die "MODPACK_INCLUDE_OPTIONAL=true is not supported in this phase"

  format="${MODPACK_FORMAT}"
  if [[ "$format" == "auto" ]]; then
    case "${MODPACK_URL}" in
      *.mrpack) format="mrpack" ;;
      *) die "MODPACK_FORMAT=auto only recognizes .mrpack URLs in this phase" ;;
    esac
  fi

  [[ "$format" == "mrpack" ]] || die "Only Modrinth mrpack install is supported in this phase"

  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/pack.mrpack"
  source="${MODPACK_URL}"

  log INFO "Installing Modrinth mrpack (experimental local mode)"
  download_modpack_file "$source" "$archive" "mrpack archive"
  if ! install_modrinth_mrpack "$archive" "$source"; then
    safe_rm_rf "$tmpdir"
    return 1
  fi
  safe_rm_rf "$tmpdir"
}

install() {
  log INFO "Install phase start"
  run_phase_hooks "pre-install"

  install_dirs
  install_eula
  install_server        # server jar
  clear_fabric_cache
  setup_server_icon

  configure_paper_configs
  generate_velocity_toml
  ensure_server_properties

  handle_reset_world_flag

  install_server_properties
  install_mods          # mods (most important)
  activate_mods         # activate mods
  install_datapacks     # datapacks
  activate_datapacks    # activate datapacks
  install_jvm_args
  install_configs
  activate_configs
  apply_paper_global_from_env
  install_plugins
  activate_plugins
  if [[ ! "${TYPE}" == "velocity" ]]; then
    install_resourcepacks
    activate_resourcepacks
  fi
  install_modpack
  install_c2me_jvm_args
  install_whitelist
  install_ops
  configure_c2me_opencl
  run_phase_hooks "post-install"

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

case "${1:-run}" in
  run)
    shift || true
    ;;
  install-only)
    INSTALL_ONLY=true
    shift || true
    ;;
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
    if ! rcon_stop_once; then
      log WARN "[shutdown] rcon-stop command failed; exiting 0 for Kubernetes preStop compatibility"
    fi
    exit 0
    ;;
esac

main() {
  log INFO "Minecraft Runtime Booting..."
  preflight
  resolve_type_auto
  detect_runtime_env
  install

  if is_true "${INSTALL_ONLY:-false}"; then
    log WARN "INSTALL_ONLY=true, skipping runtime launch and exiting"
    exit 0
  fi

  runtime
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
