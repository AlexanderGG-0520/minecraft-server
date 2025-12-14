#!/usr/bin/env bash
set -Eeuo pipefail

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] [$1] $2"; }
die() { log ERROR "$1"; exit 1; }

MC_PID=""

graceful_shutdown() {
  log INFO "Received shutdown signal"

  rm -f /data/.ready

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

# ============================================================
# F-2: Runtime Environment Detection
# ============================================================

detect_runtime_env() {
  log INFO "Detecting runtime environment..."

  # ---- CPU / Arch ----
  RUNTIME_ARCH="$(uname -m || echo unknown)"
  export RUNTIME_ARCH

  # Normalize arch
  case "${RUNTIME_ARCH}" in
    x86_64|amd64) RUNTIME_ARCH_NORM="x86_64" ;;
    aarch64|arm64) RUNTIME_ARCH_NORM="aarch64" ;;
    *) RUNTIME_ARCH_NORM="unknown" ;;
  esac
  export RUNTIME_ARCH_NORM

  # ---- OS ----
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    RUNTIME_OS="${ID:-unknown}"
    RUNTIME_OS_VERSION="${VERSION_ID:-unknown}"
  else
    RUNTIME_OS="unknown"
    RUNTIME_OS_VERSION="unknown"
  fi
  export RUNTIME_OS RUNTIME_OS_VERSION

  # ---- Container detection ----
  if grep -qa container= /proc/1/cgroup 2>/dev/null; then
    RUNTIME_CONTAINER="true"
  else
    RUNTIME_CONTAINER="unknown"
  fi
  export RUNTIME_CONTAINER

  # ---- Java version ----
  JAVA_VERSION_RAW="$(java -version 2>&1 | head -n 1 || true)"
  export JAVA_VERSION_RAW

  # Extract major version
  if [[ "${JAVA_VERSION_RAW}" =~ \"([0-9]+) ]]; then
    JAVA_MAJOR="${BASH_REMATCH[1]}"
  else
    JAVA_MAJOR="unknown"
  fi
  export JAVA_MAJOR

  # ---- Java vendor ----
  JAVA_VENDOR="$(java -XshowSettings:properties -version 2>&1 \
    | grep -i 'java.vendor =' \
    | head -n 1 \
    | awk -F'= ' '{print $2}' || true)"
  export JAVA_VENDOR

  # ---- GPU detection (future use only) ----
  if ls /dev/nvidia* >/dev/null 2>&1; then
    RUNTIME_GPU="nvidia"
  elif [[ -d /dev/dri ]]; then
    RUNTIME_GPU="dri"
  else
    RUNTIME_GPU="none"
  fi
  export RUNTIME_GPU

  # ---- Summary log ----
  log INFO "Runtime summary:"
  log INFO "  Arch        : ${RUNTIME_ARCH_NORM} (${RUNTIME_ARCH})"
  log INFO "  OS          : ${RUNTIME_OS} ${RUNTIME_OS_VERSION}"
  log INFO "  Container   : ${RUNTIME_CONTAINER}"
  log INFO "  Java        : ${JAVA_VERSION_RAW}"
  log INFO "  Java major  : ${JAVA_MAJOR}"
  log INFO "  Java vendor : ${JAVA_VENDOR}"
  log INFO "  GPU         : ${RUNTIME_GPU}"
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
      curl -fL "https://piston-data.mojang.com/v1/objects/${sha1}/server.jar" \
        -o /data/server.jar \
        || die "Failed to download vanilla server.jar"
      ;;

    fabric)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for fabric"

      if [[ -f /data/server.jar ]]; then
        log INFO "server.jar already exists, skipping"
        return
      fi

      INSTALLER_VERSION="${FABRIC_INSTALLER_VERSION:-latest}"
      LOADER_VERSION="${FABRIC_LOADER_VERSION:-latest}"

      log INFO "Installing Fabric server (MC=${VERSION}, loader=${LOADER_VERSION})"

      curl -fsSL \
        "https://meta.fabricmc.net/v2/versions/installer" \
        | jq -r '.[0].version' \
        > /tmp/fabric_installer_version

      INSTALLER_VER="$(cat /tmp/fabric_installer_version)"

      curl -fL \
        "https://meta.fabricmc.net/v2/versions/installer/${INSTALLER_VER}/${INSTALLER_VER}.jar" \
        -o /tmp/fabric-installer.jar \
        || die "Failed to download Fabric installer"

      java -jar /tmp/fabric-installer.jar \
        server \
        -mcversion "${VERSION}" \
        -loader "${LOADER_VERSION}" \
        -downloadMinecraft \
        -dir /data \
        || die "Fabric installer failed"

      # Fabric installer generates fabric-server-launch.jar
      mv /data/fabric-server-launch.jar /data/server.jar \
        || die "Fabric server jar not found"

      log INFO "Fabric server.jar ready"
      ;;

    forge)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for forge"

      if [[ -f /data/server.jar ]]; then
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
        /data \
        || die "Forge installer failed"

      # Forge generates run.sh + libraries + jar
      FORGE_JAR="$(ls /data | grep 'forge-.*-server.jar' | head -n 1)"
      [[ -f "/data/${FORGE_JAR}" ]] || die "Forge server jar not found"

      ln -sf "/data/${FORGE_JAR}" /data/server.jar
      log INFO "Forge server.jar ready"
      ;;

    neoforge)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for neoforge"

      if [[ -f /data/server.jar ]]; then
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
        /data \
        || die "NeoForge installer failed"

      NEO_JAR="$(ls /data | grep 'neoforge-.*-server.jar' | head -n 1)"
      [[ -f "/data/${NEO_JAR}" ]] || die "NeoForge server jar not found"

      ln -sf "/data/${NEO_JAR}" /data/server.jar
      log INFO "NeoForge server.jar ready"
      ;;

    paper)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for paper"

      if [[ -f /data/server.jar ]]; then
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
        -o /data/server.jar \
        || die "Failed to download Paper server.jar"

      log INFO "Paper server.jar ready"
      ;;
    
    purpur)
      [[ -n "${VERSION:-}" ]] || die "VERSION is required for purpur"

      if [[ -f /data/server.jar ]]; then
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
        -o /data/server.jar \
        || die "Failed to download Purpur server.jar"

      log INFO "Purpur server.jar ready"
      ;;

    *)
      die "install_server: TYPE=${TYPE} not implemented yet"
      ;;
  esac
}


install_jvm_args() {
  log INFO "Generating JVM args"

  JVM_ARGS_FILE="/data/jvm.args"

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
    log INFO "C2ME Hardware Acceleration disabled (guard conditions not met)"
  fi
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

  PROPS_FILE="/data/server.properties"

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

  PROPS_FILE="/data/server.properties"
  TMP_FILE="/data/server.properties.tmp"

  cp "${PROPS_FILE}" "${TMP_FILE}"

  for ENV_KEY in "${!PROP_MAP[@]}"; do
    ENV_VAL="${!ENV_KEY:-}"
    [[ -z "${ENV_VAL}" ]] && continue

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
  PROPS_FILE="/data/server.properties"

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

  : "${MODS_S3_PREFIX:=mods/latest}"
  : "${MODS_SYNC_ONCE:=true}"
  : "${MODS_REMOVE_EXTRA:=true}"

  MODS_DIR="/data/mods"
  mkdir -p "${MODS_DIR}"

  # すでに mods が存在し、1回同期モードなら何もしない
  if [[ "${MODS_SYNC_ONCE}" == "true" ]] && [[ -n "$(ls -A "${MODS_DIR}")" ]]; then
    log INFO "Mods already present, skipping sync"
    return
  fi

  log INFO "Configuring MinIO client"
  mc alias set s3 \
    "${MODS_S3_ENDPOINT}" \
    "${MODS_S3_ACCESS_KEY}" \
    "${MODS_S3_SECRET_KEY}" \
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

  log INFO "Mods installed successfully"
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

  CONFIG_DIR="/data/config"
  mkdir -p "${CONFIG_DIR}"

  # すでに config が存在し、1回同期モードなら何もしない
  if [[ "${CONFIGS_SYNC_ONCE}" == "true" ]] && [[ -n "$(ls -A "${CONFIG_DIR}")" ]]; then
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

  PLUGINS_DIR="/data/plugins"
  mkdir -p "${PLUGINS_DIR}"

  # 既に plugins があり、1回同期モードなら何もしない
  if [[ "${PLUGINS_SYNC_ONCE}" == "true" ]] && [[ -n "$(ls -A "${PLUGINS_DIR}")" ]]; then
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

  DATAPACKS_DIR="/data/world/datapacks"
  mkdir -p "${DATAPACKS_DIR}"

  # 既に datapacks があり、1回同期モードならスキップ
  if [[ "${DATAPACKS_SYNC_ONCE}" == "true" ]] && [[ -n "$(ls -A "${DATAPACKS_DIR}")" ]]; then
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

  RP_DIR="/data/resourcepacks"
  mkdir -p "${RP_DIR}"

  # 既に存在し、1回同期ならスキップ
  if [[ "${RESOURCEPACKS_SYNC_ONCE}" == "true" ]] && [[ -n "$(ls -A "${RP_DIR}")" ]]; then
    log INFO "Resourcepacks already present, skipping sync"
  else
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
  fi

  # ---- server.properties 連動（任意） ----
  if [[ "${RESOURCEPACKS_AUTO_APPLY}" == "true" ]] && [[ -n "${RESOURCEPACK_URL:-}" ]]; then
    log INFO "Applying resource-pack settings to server.properties"

    : "${RESOURCEPACK_SHA1:=}"

    sed -i \
      -e "s|^resource-pack=.*|resource-pack=${RESOURCEPACK_URL}|" \
      -e "s|^resource-pack-sha1=.*|resource-pack-sha1=${RESOURCEPACK_SHA1}|" \
      -e "s|^require-resource-pack=.*|require-resource-pack=${RESOURCEPACK_REQUIRED}|" \
      /data/server.properties || true
  fi

  log INFO "Resourcepacks installed successfully"
}

reset_world() {
  log INFO "Requested world reset"

  # ---- Safety check 1: explicit confirmation ----
  if [[ "${RESET_WORLD_CONFIRM:-}" != "yes" ]]; then
    die "RESET_WORLD_CONFIRM=yes is required to reset world"
  fi

  WORLD_DIR="/data/world"

  # ---- Safety check 2: directory sanity ----
  if [[ ! -d "${WORLD_DIR}" ]]; then
    log INFO "World directory does not exist, nothing to reset"
    return
  fi

  if [[ "${WORLD_DIR}" == "/" || "${WORLD_DIR}" == "/data" ]]; then
    die "Unsafe WORLD_DIR detected: ${WORLD_DIR}"
  fi

  log INFO "Resetting world at ${WORLD_DIR}"

  # ---- Step 1: mark NotReady ----
  rm -f /data/.ready

  # ---- Step 2: optional backup ----
  if [[ "${RESET_WORLD_BACKUP:-true}" == "true" ]]; then
    TS="$(date -u +'%Y%m%d-%H%M%S')"
    BACKUP_DIR="/data/backups"
    mkdir -p "${BACKUP_DIR}"

    log INFO "Creating world backup"
    tar -czf "${BACKUP_DIR}/world-${TS}.tar.gz" -C /data world \
      || die "World backup failed"
  fi

  # ---- Step 3: delete world contents only ----
  log INFO "Deleting world contents"
  rm -rf "${WORLD_DIR:?}/"*

  log INFO "World reset completed successfully"
}

# ============================================================
# Optimize Mods (F-1)
# ============================================================

: "${OPTIMIZE_MODE:=auto}"                 # auto|off|force
: "${OPTIMIZE_S3_BUCKET:=}"                # required if optimize enabled
: "${OPTIMIZE_S3_PREFIX:=optimization}"    # default prefix

: "${OPTIMIZE_LITHIUM:=true}"
: "${OPTIMIZE_FERRITECORE:=true}"
: "${OPTIMIZE_MODERNFIX:=true}"
: "${OPTIMIZE_STRICT:=false}"

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

install_optimize_mods() {
  log INFO "Installing optimization mods..."

  if [[ "${OPTIMIZE_MODE}" == "off" ]]; then
    log INFO "OPTIMIZE_MODE=off, skipping"
    return 0
  fi

  local fam
  fam="$(opt_type_family)"

  if [[ "$fam" == "unknown" ]]; then
    if [[ "${OPTIMIZE_MODE}" == "force" ]]; then
      log WARN "Unknown TYPE='${TYPE:-}', but OPTIMIZE_MODE=force, continuing"
    else
      log INFO "TYPE='${TYPE:-}' not eligible for optimize mods, skipping"
      return 0
    fi
  fi

  # If nothing enabled for this family, skip
  if [[ "$fam" != "unknown" ]] && ! opt_required_any_enabled "$fam"; then
    log INFO "All optimize mods disabled by env for family=$fam, skipping"
    return 0
  fi

  [[ -n "${OPTIMIZE_S3_BUCKET}" ]] || die "OPTIMIZE_S3_BUCKET is required when optimize mods enabled"

  opt_mc_configure_alias

  local cache_dir="${OPT_MANAGED_DIR}/${TYPE}"
  local src="s3/${OPTIMIZE_S3_BUCKET}/${OPTIMIZE_S3_PREFIX}/${TYPE}"

  log INFO "Sync optimize mods from: ${src} -> ${cache_dir}"
  opt_mirror_from_s3 "$src" "$cache_dir" || {
    if opt_bool "$OPTIMIZE_STRICT"; then
      die "Failed to mirror optimize mods (strict mode)"
    fi
    log WARN "Failed to mirror optimize mods, continuing without them"
    return 0
  }

  # Optional: basic filtering by family (soft)
  # We *don't* delete jars from cache; we just link everything.
  # If you want hard filtering later, do it in S3 layout, not here.

  if opt_install_links "$cache_dir" "${DATA_DIR}/mods"; then
    log INFO "Optimization mods linked into mods/ (prefix: ${OPT_LINK_PREFIX})"
  else
    if opt_bool "$OPTIMIZE_STRICT"; then
      die "No optimization mod jars found after sync (strict mode)"
    fi
    log WARN "No optimize mod jars found in ${cache_dir}"
  fi

  return 0
}

install() {
  log INFO "Install phase start"
  install_dirs
  install_eula
  install_server
  install_jvm_args
  install_c2me_jvm_args
  install_server_properties
  install_mods
  install_configs
  install_plugins
  install_datapacks
  install_resourcepacks
  if [[ "${RESET_WORLD:-false}" == "true" ]]; then
    reset_world
  fi
  install_optimize_mods
  log INFO "Install phase completed (partial)"
}

runtime() {
  log INFO "Starting Minecraft runtime"

  [[ -f /data/server.jar ]] || die "server.jar not found"
  [[ -f /data/jvm.args ]]  || die "jvm.args not found"

  rm -f /data/.ready

  java @"${JVM_ARGS_FILE:-/data/jvm.args}" -jar /data/server.jar nogui &
  MC_PID=$!

  sleep "${READY_DELAY:-5}"

  if kill -0 "${MC_PID}" 2>/dev/null; then
    touch /data/.ready
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

