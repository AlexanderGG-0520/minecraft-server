#!/usr/bin/env bash
set -Eeuo pipefail

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] [$1] $2"; }
die() { log ERROR "$1"; exit 1; }

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

# Configs
: "${CONFIGS_ENABLED:=true}"
: "${CONFIGS_S3_PREFIX:=configs/latest}"
: "${CONFIGS_SYNC_ONCE:=true}"
: "${CONFIGS_REMOVE_EXTRA:=true}"

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
  mc alias set mods3 \
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
    "mods3/${MODS_S3_BUCKET}/${MODS_S3_PREFIX}" \
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
  mc alias set cfg3 \
    "${CONFIGS_S3_ENDPOINT}" \
    "${CONFIGS_S3_ACCESS_KEY}" \
    "${CONFIGS_S3_SECRET_KEY}" \
    || die "Failed to configure MinIO client (configs)"

  REMOVE_FLAG=""
  [[ "${CONFIGS_REMOVE_EXTRA}" == "true" ]] && REMOVE_FLAG="--remove"

  log INFO "Syncing configs from s3://${CONFIGS_S3_BUCKET}/${CONFIGS_S3_PREFIX}"

  mc mirror \
    --overwrite \
    ${REMOVE_FLAG} \
    "cfg3/${CONFIGS_S3_BUCKET}/${CONFIGS_S3_PREFIX}" \
    "${CONFIG_DIR}" \
    || die "Failed to sync configs from MinIO"

  log INFO "Configs installed successfully"
}

install() {
  log INFO "Install phase start"
  install_dirs
  install_eula
  install_server
  install_jvm_args
  install_server_properties
  install_mods
  install_configs
  log INFO "Install phase completed (partial)"
}

runtime() {
  log INFO "Starting Minecraft runtime"
  [[ -f /data/server.jar ]] || die "server.jar not found"
  [[ -f /data/jvm.args ]]  || die "jvm.args not found"

  rm -f /data/.ready

  java @"${JVM_ARGS_FILE:-/data/jvm.args}" -jar /data/server.jar nogui &
  MC_PID=$!

  sleep 5
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
  install
  runtime
}

main "$@"
