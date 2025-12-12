#!/bin/bash
set -euo pipefail

log() { echo "[server.properties] $*"; }

OUT="/data/server.properties"

# server.properties をクリーンに再生成
: > "$OUT"

log "Generating server.properties from environment..."

# ------------------------------------------------------------
# 1. 環境変数 → server.properties のマッピング定義
# ------------------------------------------------------------
declare -A MAP=(
  [SERVER_PORT]="server-port"
  [SERVER_IP]="server-ip"
  [LEVEL_NAME]="level-name"
  [LEVEL_SEED]="level-seed"
  [LEVEL_TYPE]="level-type"
  [ONLINE_MODE]="online-mode"
  [WHITE_LIST]="white-list"
  [MAX_PLAYERS]="max-players"
  [VIEW_DISTANCE]="view-distance"
  [SIMULATION_DISTANCE]="simulation-distance"
  [DIFFICULTY]="difficulty"
  [ENABLE_COMMAND_BLOCK]="enable-command-block"
  [SPAWN_PROTECTION]="spawn-protection"
  [MOTD]="motd"
  [PVP]="pvp"
  [ALLOW_FLIGHT]="allow-flight"
  [GAMEMODE]="gamemode"
  [HARDCORE]="hardcore"
  [ENABLE_RCON]="enable-rcon"
  [RCON_PORT]="rcon-port"
  [RCON_PASSWORD]="rcon.password"
  [ENABLE_QUERY]="enable-query"
  [QUERY_PORT]="query.port"
  [MAX_TICK_TIME]="max-tick-time"
  [MAX_BUILD_HEIGHT]="max-build-height"
  [FORCE_GAMEMODE]="force-gamemode"
  [GENERATE_STRUCTURES]="generate-structures"
  [NETWORK_COMPRESSION_THRESHOLD]="network-compression-threshold"
  [USE_NATIVE_TRANSPORT]="use-native-transport"
)

# ------------------------------------------------------------
# 2. 変数がセットされているものだけ server.properties に出力
# ------------------------------------------------------------
for ENV_NAME in "${!MAP[@]}"; do
  KEY="${MAP[$ENV_NAME]}"

  # 未指定ならスキップ → バニラデフォルトに委ねる
  if [[ -z "${!ENV_NAME:-}" ]]; then
    continue
  fi

  VALUE="${!ENV_NAME}"
  printf "%s=%s\n" "$KEY" "$VALUE" >> "$OUT"
done

# ------------------------------------------------------------
# 3. 動的設定（TYPE などで自動補完したいもの）
# ------------------------------------------------------------

# Fabric / Paper は若干異なる値を要求する場合があるが、
# 基本的に server.properties は TYPE に依存しないため、
# 現時点では TYPE 固有処理は不要。
# （必要になったらここに分岐を書く）

log "server.properties generated successfully."
