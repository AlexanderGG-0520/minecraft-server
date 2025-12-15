#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Global paths
# ============================================================

: "${DATA_DIR:=/data}"
: "${JVM_ARGS_FILE:=${DATA_DIR}/jvm.args}"

# ============================================================
# Runtime detection defaults (set -u safety)
# ============================================================

: "${JAVA_MAJOR:=unknown}"
: "${JAVA_VERSION_RAW:=unknown}"
: "${JAVA_VENDOR:=unknown}"

: "${RUNTIME_ARCH_NORM:=unknown}"
: "${RUNTIME_CONTAINER:=unknown}"
: "${RUNTIME_GPU:=none}"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] [$1] $2"; }
die() { log ERROR "$1"; exit 1; }

MC_PID=""

graceful_shutdown() {
  log INFO "Received shutdown signal"

  rm -f "${DATA_DIR}/.ready"


  if [[ -n "${MC_PID}" ]] && kill -0 "${MC_PID}" 2>/dev/null; then
    kill "${MC_PID}"
    wait "${MC_PID}"
  fi

  log INFO "Shutdown complete"
  exit 0
}

trap graceful_shutdown SIGTERM SIGINT

# ============================================================
# Environment defaults (non server.properties)
# ============================================================

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

preflight() {
  log INFO "Preflight checks..."

  [[ -d "${DATA_DIR}" ]] || die "${DATA_DIR} does not exist"
  touch ${DATA_DIR}/.write_test 2>/dev/null || die "${DATA_DIR} is not writable"
  rm -f ${DATA_DIR}/.write_test

  [[ -n "${EULA:-}" ]] || die "EULA is not set"

  case "${TYPE:-auto}" in
    auto|fabric|forge|neoforge|quilt|paper|vanilla) ;;
    *) die "Invalid TYPE: ${TYPE}" ;;
  esac

  if [[ "${TYPE:-auto}" != "auto" && -z "${VERSION:-}" ]]; then
    die "VERSION must be set when TYPE is not auto"
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
  [[ -d /dev/dri || -e /dev/nvidia0 ]] || return 1

  return 0
}

install_dirs() {
  log INFO "Preparing directory structure"

  mkdir -p \
    ${DATA_DIR}/logs \
    ${DATA_DIR}/mods \
    ${DATA_DIR}/config \
    ${DATA_DIR}/world

  # 権限トラブルの早期発見（非root想定なら特に重要）
  touch ${DATA_DIR}/logs/.perm_test 2>/dev/null || die "${DATA_DIR}/logs is not writable"
  rm -f ${DATA_DIR}/logs/.perm_test

  log INFO "Directory structure ready"
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

reset_world() {
  log INFO "Requested world reset"

  FLAG_FILE="${DATA_DIR}/reset-world.flag"  # フラグファイルの場所

  # ---- Safety check 1: explicit confirmation ----
  if [[ ! -f "${FLAG_FILE}" ]]; then
    log INFO "reset-world.flag file is missing, cannot proceed with world reset"
    return  # フラグが見つからない場合は終了
  fi

  WORLD_DIR="${DATA_DIR}/world"

  # ---- Safety check 2: directory sanity ----
  if [[ ! -d "${WORLD_DIR}" ]]; then
    log INFO "World directory does not exist, nothing to reset"
    return
  fi

  if [[ "${WORLD_DIR}" == "/" || "${WORLD_DIR}" == "${DATA_DIR}" ]]; then
    log ERROR "Unsafe WORLD_DIR detected: ${WORLD_DIR}"
    return  # 不正なディレクトリの場合
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

  # ---- Step 3: delete world contents only ----
  log INFO "Deleting world contents"
  rm -rf "${WORLD_DIR:?}/"*

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

    log WARN "reset-world.flag detected, proceeding to reset world"

    if (( NOW - MTIME > MAX_AGE )); then
      log ERROR "reset-world.flag expired (older than ${MAX_AGE}s), resetting aborted"
      return  # Stop further execution but do not die
    fi
  fi

  reset_world

  # consume flag (ONE-SHOT)
  rm -f "$FLAG"
  log INFO "reset-world.flag consumed"
}

install_server() {
  log INFO "Resolving server (TYPE=${TYPE}, VERSION=${VERSION:-auto})"

  case "${TYPE}" in
    auto)
      if [[ ! -f ${DATA_DIR}/server.jar ]]; then
        log INFO "Creating dummy server.jar (auto mode)"
        echo "dummy server jar" > ${DATA_DIR}/server.jar
      else
        log INFO "server.jar already exists, skipping"
      fi
      ;;

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

  # ↓ ここから installer 実行


      # ---- resolve loader ----
      LOADER_VERSION="${FABRIC_LOADER_VERSION:-latest}"
      if [[ "${LOADER_VERSION}" == "latest" ]]; then
        LOADER_VERSION="$(curl -fsSL \
          "https://meta.fabricmc.net/v2/versions/loader/${VERSION}" \
          | jq -r '.[0].loader.version')" \
          || die "Failed to resolve Fabric loader version"
      fi

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


    forge)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for forge"

      if [[ -f ${DATA_DIR}/server.jar ]]; then
        log INFO "server.jar already exists, skipping"
        return
      fi

      FORGE_VER="${FORGE_VERSION:-latest}"
      log INFO "Installing Forge server (MC=${VERSION}, forge=${FORGE_VER})"

      # Forge version metadata
      FORGE_META_URL="https://files.minecraftforge.net/net/minecraftforge/forge/index_${VERSION}.html"
      FORGE_VER="$(curl -fsSL ${FORGE_META_URL} \
        | grep -oP 'forge-\K[0-9\.]+' \
        | head -n 1)"

      [[ -n "${FORGE_VER}" ]] || die "Failed to resolve Forge version"

      INSTALLER="forge-${VERSION}-${FORGE_VER}-installer.jar"

      curl -fL \
        "https://maven.minecraftforge.net/net/minecraftforge/forge/${VERSION}-${FORGE_VER}/${INSTALLER}" \
        -o "/tmp/${INSTALLER}" \
        || die "Failed to download Forge installer"

      java -jar "/tmp/${INSTALLER}" \
        --installServer \
        ${DATA_DIR} \
        || die "Forge installer failed"

      # Forge generates run.sh + libraries + jar
      FORGE_JAR="$(ls ${DATA_DIR} | grep 'forge-.*-server.jar' | head -n 1)"
      [[ -f "${DATA_DIR}/${FORGE_JAR}" ]] || die "Forge server jar not found"

      ln -sf "${DATA_DIR}/${FORGE_JAR}" ${DATA_DIR}/server.jar
      log INFO "Forge server.jar ready"
      ;;

    neoforge)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for neoforge"

      if [[ -f ${DATA_DIR}/server.jar ]]; then
        log INFO "server.jar already exists, skipping"
        return
      fi

      NEO_VER="${NEOFORGE_VERSION:-latest}"
      log INFO "Installing NeoForge server (MC=${VERSION}, neoforge=${NEO_VER})"

      # NeoForge metadata API
      META_URL="https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge"
      NEO_VER="$(curl -fsSL ${META_URL} | jq -r '.[0].version')"

      [[ -n "${NEO_VER}" ]] || die "Failed to resolve NeoForge version"

      INSTALLER="neoforge-${NEO_VER}-installer.jar"

      curl -fL \
        "https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEO_VER}/${INSTALLER}" \
        -o "/tmp/${INSTALLER}" \
        || die "Failed to download NeoForge installer"

      java -jar "/tmp/${INSTALLER}" \
        --installServer \
        ${DATA_DIR} \
        || die "NeoForge installer failed"

      NEO_JAR="$(ls ${DATA_DIR} | grep 'neoforge-.*-server.jar' | head -n 1)"
      [[ -f "${DATA_DIR}/${NEO_JAR}" ]] || die "NeoForge server jar not found"

      ln -sf "${DATA_DIR}/${NEO_JAR}" ${DATA_DIR}/server.jar
      log INFO "NeoForge server.jar ready"
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
        BUILD="$(curl -fsSL \
          "https://api.papermc.io/v2/projects/paper/versions/${VERSION}" \
          | jq -r '.builds[-1]')" || die "Failed to resolve Paper build"
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

      log INFO "Installing Purpur server (MC=${VERSION}, build=${BUILD})"

      if [[ "${BUILD}" == "latest" ]]; then
        BUILD="$(curl -fsSL \
          "https://api.purpurmc.org/v2/purpur/${VERSION}" \
          | jq -r '.builds.latest')" || die "Failed to resolve Purpur build"
      fi

      JAR_NAME="purpur-${VERSION}-${BUILD}.jar"

      curl -fL \
        "https://api.purpurmc.org/v2/purpur/${VERSION}/${BUILD}/download" \
        -o ${DATA_DIR}/server.jar \
        || die "Failed to download Purpur server.jar"

      log INFO "Purpur server.jar ready"
      ;;

    *)
      die "install_server: TYPE=${TYPE} not implemented yet"
      ;;
  esac
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

  : "${MODS_S3_PREFIX:=fabric/hardcore/mods}"
  : "${MODS_SYNC_ONCE:=true}"
  : "${MODS_REMOVE_EXTRA:=true}"

  MODS_DIR="${DATA_DIR}/mods"
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

  log INFO "Mods installed: $(ls "${MODS_DIR}"/*.jar | wc -l)"
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

  # 既にあれば尊重（ユーザー上書き可能）
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

  : "${CONFIGS_S3_PREFIX:=configs/latest}"
  : "${CONFIGS_SYNC_ONCE:=true}"
  : "${CONFIGS_REMOVE_EXTRA:=true}"

  CONFIG_DIR="${DATA_DIR}/config"
  mkdir -p "${CONFIG_DIR}"

  # すでに config が存在し、1回同期モードなら何もしない
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

install_plugins() {
  log INFO "Install plugins (Paper only)"

  [[ "${PLUGINS_ENABLED:-true}" == "true" ]] || {
    log INFO "Plugins disabled"
    return
  }

  # Paper 以外では無効
  if [[ "${TYPE:-auto}" != "paper" ]]; then
    log INFO "TYPE=${TYPE}, skipping plugins"
    return
  fi

  [[ -n "${PLUGINS_S3_BUCKET:-}" ]] || {
    log INFO "PLUGINS_S3_BUCKET not set, skipping plugins"
    return
  }

  : "${PLUGINS_S3_PREFIX:=plugins/latest}"
  : "${PLUGINS_SYNC_ONCE:=true}"
  : "${PLUGINS_REMOVE_EXTRA:=true}"

  PLUGINS_DIR="${DATA_DIR}/plugins"
  mkdir -p "${PLUGINS_DIR}"

  # 既に plugins があり、1回同期モードなら何もしない
  if [[ "${PLUGINS_SYNC_ONCE}" == "true" ]] \
    && [[ -n "$(ls -A "${PLUGINS_DIR}")" ]] \
    && [[ "${PLUGINS_REMOVE_EXTRA}" != "true" ]]; then
    log INFO "Plugins already present, skipping sync"
    return
  fi


  log INFO "Configuring MinIO client for plugins"
  mc alias set s3 \
    "${S3_ENDPOINT}" \
    "${S3_ACCESS_KEY}" \
    "${S3_SECRET_KEY}" \
    || die "Failed to configure MinIO client"


  REMOVE_FLAG=""
  [[ "${PLUGINS_REMOVE_EXTRA}" == "true" ]] && REMOVE_FLAG="--remove"

  log INFO "Syncing plugins from s3://${PLUGINS_S3_BUCKET}/${PLUGINS_S3_PREFIX}"

mc mirror \
  --overwrite \
  ${REMOVE_FLAG} \
  "s3/${PLUGINS_S3_BUCKET}/${PLUGINS_S3_PREFIX}" \
  "${PLUGINS_DIR}" \
    || die "Failed to sync plugins from MinIO"

  log INFO "Plugins installed successfully"
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

  : "${DATAPACKS_S3_PREFIX:=datapacks/latest}"
  : "${DATAPACKS_SYNC_ONCE:=true}"
  : "${DATAPACKS_REMOVE_EXTRA:=true}"

  DATAPACKS_DIR="${DATA_DIR}/world/datapacks"
  mkdir -p "${DATAPACKS_DIR}"

  # 既に datapacks があり、1回同期モードならスキップ
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

  : "${RESOURCEPACKS_S3_PREFIX:=resourcepacks/latest}"
  : "${RESOURCEPACKS_SYNC_ONCE:=true}"
  : "${RESOURCEPACKS_REMOVE_EXTRA:=true}"
  : "${RESOURCEPACKS_AUTO_APPLY:=true}"
  : "${RESOURCEPACK_REQUIRED:=false}"

  RP_DIR="${DATA_DIR}/resourcepacks"
  mkdir -p "${RP_DIR}"

  # 既に存在し、1回同期ならスキップ
  if [[ "${RESOURCEPACKS_SYNC_ONCE}" == "true" ]] \
   && [[ -n "$(ls -A "${RP_DIR}")" ]] \
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
  
  # ---- server.properties 連動（任意） ----
  if [[ "${RESOURCEPACKS_AUTO_APPLY}" == "true" ]] && [[ -n "${RESOURCEPACK_URL:-}" ]]; then
    log INFO "Applying resource-pack settings to server.properties"

    : "${RESOURCEPACK_SHA1:=}"

    sed -i \
      -e "s|^resource-pack=.*|resource-pack=${RESOURCEPACK_URL}|" \
      -e "s|^resource-pack-sha1=.*|resource-pack-sha1=${RESOURCEPACK_SHA1}|" \
      -e "s|^require-resource-pack=.*|require-resource-pack=${RESOURCEPACK_REQUIRED}|" \
      ${DATA_DIR}/server.properties || true
  fi

  log INFO "Resourcepacks installed successfully"
}

# ===========================================
# server.properties env -> key mapping
# ===========================================
declare -A PROP_MAP=(
  # --- 基本 ---
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

  # --- Phase A: 管理・挙動 ---
  [ENABLE_WHITELIST]="enable-whitelist"
  [WHITE_LIST]="white-list"
  [ENFORCE_WHITELIST]="enforce-whitelist"
  [OP_PERMISSION_LEVEL]="op-permission-level"
  [FUNCTION_PERMISSION_LEVEL]="function-permission-level"
  [LOG_IPS]="log-ips"
  [BROADCAST_CONSOLE_TO_OPS]="broadcast-console-to-ops"
  [BROADCAST_RCON_TO_OPS]="broadcast-rcon-to-ops"

  # --- Phase B: パフォーマンス・安定性 ---
  [MAX_TICK_TIME]="max-tick-time"
  [SYNC_CHUNK_WRITES]="sync-chunk-writes"
  [ENTITY_BROADCAST_RANGE_PERCENTAGE]="entity-broadcast-range-percentage"
  [MAX_CHAINED_NEIGHBOR_UPDATES]="max-chained-neighbor-updates"

  # --- Phase C: Query / RCON / 外部連携 ---
  [ENABLE_QUERY]="enable-query"
  [QUERY_PORT]="query.port"
  [ENABLE_RCON]="enable-rcon"
  [RCON_PORT]="rcon.port"
  [RCON_PASSWORD]="rcon.password"
  [RESOURCE_PACK]="resource-pack"
  [RESOURCE_PACK_SHA1]="resource-pack-sha1"
  [REQUIRE_RESOURCE_PACK]="require-resource-pack"
)

generate_server_properties() {
  log INFO "Generating server.properties"

  PROPS_FILE="${DATA_DIR}/server.properties"

  # defaults（必要なものだけ）
  : "${MOTD:=Welcome to the server}"
  : "${DIFFICULTY:=easy}"
  : "${GAMEMODE:=survival}"
  : "${HARDCORE:=false}"
  : "${FORCE_GAMEMODE:=false}"
  : "${ALLOW_FLIGHT:=false}"
  : "${SPAWN_PROTECTION:=16}"
  : "${MAX_PLAYERS:=20}"
  : "${VIEW_DISTANCE:=10}"
  : "${SIMULATION_DISTANCE:=10}"

  # --- Phase A defaults ---
  : "${ENABLE_WHITELIST:=false}"
  : "${WHITE_LIST:=false}"
  : "${ENFORCE_WHITELIST:=false}"
  : "${OP_PERMISSION_LEVEL:=4}"
  : "${FUNCTION_PERMISSION_LEVEL:=2}"
  : "${LOG_IPS:=true}"
  : "${BROADCAST_CONSOLE_TO_OPS:=true}"
  : "${BROADCAST_RCON_TO_OPS:=true}"

  # --- Phase B defaults ---
  : "${MAX_TICK_TIME:=60000}"
  : "${SYNC_CHUNK_WRITES:=true}"
  : "${ENTITY_BROADCAST_RANGE_PERCENTAGE:=100}"
  : "${MAX_CHAINED_NEIGHBOR_UPDATES:=1000000}"

  # --- Phase C defaults ---
  : "${ENABLE_QUERY:=false}"
  : "${QUERY_PORT:=25565}"

  : "${ENABLE_RCON:=false}"
  : "${RCON_PORT:=25575}"
  : "${RCON_PASSWORD:=}"

  : "${RESOURCE_PACK:=}"
  : "${RESOURCE_PACK_SHA1:=}"
  : "${REQUIRE_RESOURCE_PACK:=false}"


  {
    for ENV_KEY in "${!PROP_MAP[@]}"; do
      PROP_KEY="${PROP_MAP[$ENV_KEY]}"
      ENV_VAL="${!ENV_KEY}"
      echo "${PROP_KEY}=${ENV_VAL}"
    done
  } > "${PROPS_FILE}"

  log INFO "server.properties generated"
}

apply_server_properties_diff() {
  log INFO "Applying server.properties diff from environment"

  PROPS_FILE="${DATA_DIR}/server.properties"
  TMP_FILE="${DATA_DIR}/server.properties.tmp"

  cp "${PROPS_FILE}" "${TMP_FILE}"

  for ENV_KEY in "${!PROP_MAP[@]}"; do
    if [[ -z "${!ENV_KEY+x}" ]]; then
      continue
    fi

    ENV_VAL="${!ENV_KEY}"
    PROP_KEY="${PROP_MAP[$ENV_KEY]}"

    if grep -q "^${PROP_KEY}=" "${TMP_FILE}"; then
      sed -i "s|^${PROP_KEY}=.*|${PROP_KEY}=${ENV_VAL}|" "${TMP_FILE}"
    else
      echo "${PROP_KEY}=${ENV_VAL}" >> "${TMP_FILE}"
    fi
  done


  mv "${TMP_FILE}" "${PROPS_FILE}"
  log INFO "server.properties diff applied"
}

install_server_properties() {
  PROPS_FILE="${DATA_DIR}/server.properties"

  if [[ ! -f "${PROPS_FILE}" ]]; then
    generate_server_properties
    return
  fi

  if [[ "${OVERRIDE_SERVER_PROPERTIES:-false}" == "true" ]]; then
    generate_server_properties
    return
  fi

  if [[ "${APPLY_SERVER_PROPERTIES_DIFF:-false}" == "true" ]]; then
    apply_server_properties_diff
  else
    log INFO "server.properties exists, no changes applied"
  fi
}

UUID_CACHE_FILE="${DATA_DIR}/.uuid-cache.json"

init_uuid_cache() {
  [[ -f "$UUID_CACHE_FILE" ]] || echo "{}" > "$UUID_CACHE_FILE"
}

uuid_for_player() {
  local name="$1"

  # cache hit
  local cached
  cached=$(jq -r --arg n "$name" '.[$n] // empty' "$UUID_CACHE_FILE")
  if [[ -n "$cached" ]]; then
    echo "$cached"
    return
  fi

  # Mojang API
  local uuid
  uuid=$(curl -fsSL \
    "https://api.mojang.com/users/profiles/minecraft/${name}" \
    | jq -r '.id // empty')

  [[ -z "$uuid" ]] && return

  # cache write
  jq --arg n "$name" --arg u "$uuid" \
    '. + {($n): $u}' \
    "$UUID_CACHE_FILE" > "${UUID_CACHE_FILE}.tmp" \
    && mv "${UUID_CACHE_FILE}.tmp" "$UUID_CACHE_FILE"

  echo "$uuid"
}

parse_csv() {
  echo "$1" | tr ',' '\n' | sed '/^$/d'
}

uuid_with_hyphen() {
  local u="$1"

  # 32 hex → 8-4-4-4-12
  echo "${u:0:8}-${u:8:4}-${u:12:4}-${u:16:4}-${u:20:12}"
}

install_whitelist() {
  local FILE="${DATA_DIR}/whitelist.json"

  [[ "${ENABLE_WHITELIST:-false}" != "true" ]] && return
  [[ -z "${WHITELIST_USERS:-}" ]] && return

  log INFO "Generating whitelist.json"

  {
    echo "["
    local first=true
    for name in $(parse_csv "${WHITELIST_USERS}"); do
      uuid=$(uuid_for_player "$name")
      [[ -z "$uuid" ]] && continue

      [[ "$first" != true ]] && echo ","
      first=false

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

install_ops() {
  local FILE="${DATA_DIR}/ops.json"

  [[ -z "${OPS_USERS:-}" ]] && return

  log INFO "Generating ops.json"

  {
    echo "["
    local first=true
    for name in $(parse_csv "${OPS_USERS}"); do
      uuid=$(uuid_for_player "$name")
      [[ -z "$uuid" ]] && continue

      [[ "$first" != true ]] && echo ","
      first=false

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
  # 1. NVIDIA device node
  # ------------------------------------------------------------
  if [ ! -e /dev/nvidia0 ]; then
    log INFO "No NVIDIA device node found"
    return 1
  fi
  log INFO "NVIDIA device node found"

  # ------------------------------------------------------------
  # 2. OpenCL loader
  # ------------------------------------------------------------
  if ! ldconfig -p 2>/dev/null | grep -q "libOpenCL.so"; then
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
  # 4. clinfo sanity check
  #   - platform must exist
  #   - device type must be GPU
  # ------------------------------------------------------------
  if ! clinfo 2>/dev/null | grep -q "Platform Name"; then
    log WARN "clinfo did not report any OpenCL platform"
    return 1
  fi

  if ! clinfo 2>/dev/null | grep -q "Device Type.*GPU"; then
    log WARN "clinfo did not report a GPU device"
    return 1
  fi

  # ------------------------------------------------------------
  # 5. NVIDIA OpenCL platform guard
  # ------------------------------------------------------------
  if ! clinfo 2>/dev/null | grep -qi "NVIDIA"; then
    log WARN "OpenCL platform is not NVIDIA"
    return 1
  fi

  log INFO "OpenCL GPU detected and usable"
  return 0
}

configure_c2me_opencl() {
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
  handle_reset_world_flag
  install_server
  install_mods
  install_jvm_args
  install_c2me_jvm_args
  install_configs
  install_plugins
  install_datapacks
  install_resourcepacks
  install_server_properties
  install_whitelist
  install_ops
  configure_c2me_opencl
  log INFO "Install phase completed (partial)"
}

runtime() {
  log INFO "Starting Minecraft runtime"

  [[ -f "${DATA_DIR}/server.jar" ]] || die "server.jar not found"
  [[ -f "${DATA_DIR}/jvm.args" ]]  || die "jvm.args not found"

  rm -f "${DATA_DIR}/.ready"

  cd "${DATA_DIR}" || die "Failed to cd to ${DATA_DIR}"

  if [[ "${TYPE}" == "fabric" ]]; then
    java @"${JVM_ARGS_FILE}" -jar "${DATA_DIR}/fabric-server-launch.jar" nogui &
  else
    java @"${JVM_ARGS_FILE}" -jar "${DATA_DIR}/server.jar" nogui &
  fi
  MC_PID=$!

  sleep "${READY_DELAY:-5}"

  if kill -0 "${MC_PID}" 2>/dev/null; then
    touch "${DATA_DIR}/.ready"
    log INFO "Server marked as ready"
  else
    die "Minecraft process exited early"
  fi

  wait "${MC_PID}"
}


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