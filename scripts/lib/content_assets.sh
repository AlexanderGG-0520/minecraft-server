# shellcheck shell=bash

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
