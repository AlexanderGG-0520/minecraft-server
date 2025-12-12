#!/bin/bash
set -euo pipefail

OUT=/data/server.properties
BASE=/opt/mc/base/server.properties.base

cp "$BASE" "$OUT"

set_prop() {
  local key="$1" env="$2"
  local val="${!env:-}"
  [[ -n "$val" ]] && sed -i "s|^${key}=.*|${key}=${val}|" "$OUT"
}

set_prop motd MOTD
set_prop difficulty DIFFICULTY
set_prop gamemode MODE
set_prop max-players MAX_PLAYERS
set_prop online-mode ONLINE_MODE
set_prop allow-flight ALLOW_FLIGHT
set_prop pvp PVP
set_prop hardcore HARDCORE
set_prop level-seed SEED
set_prop view-distance VIEW_DISTANCE
set_prop simulation-distance SIMULATION_DISTANCE
set_prop server-port SERVER_PORT
set_prop enable-command-block ENABLE_COMMAND_BLOCK
set_prop spawn-protection SPAWN_PROTECTION
