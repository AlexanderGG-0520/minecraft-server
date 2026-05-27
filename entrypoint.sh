#!/usr/bin/env bash
set -Eeuo pipefail

ENTRYPOINT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/lib/logging.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/logging.sh"
# shellcheck source=scripts/lib/filesystem.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/filesystem.sh"
# shellcheck source=scripts/lib/runtime.sh
source "${ENTRYPOINT_DIR%/}/scripts/lib/runtime.sh"
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
