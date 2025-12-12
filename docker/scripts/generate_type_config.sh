#!/bin/bash
set -euo pipefail

log() { echo "[type-config] $*"; }

TYPE="${TYPE:-vanilla}"
DATA="/data"

log "Generating TYPE-specific config for TYPE=${TYPE}"

case "$TYPE" in

  # ============================================================
  # Paper
  # ============================================================
  paper)
    log "Generating Paper configuration..."

    cat > "${DATA}/paper-global.yml" << 'EOF'
settings:
  velocity-support:
    enabled: false
    online-mode: true
EOF

    cat > "${DATA}/spigot.yml" << 'EOF'
settings:
  debug: false
world-settings:
  default:
    verbose: false
EOF

    cat > "${DATA}/bukkit.yml" << 'EOF'
settings:
  allow-end: true
spawn-limits:
  monsters: 70
EOF
    ;;


  # ============================================================
  # Purpur
  # ============================================================
  purpur)
    log "Generating Purpur configuration..."

    cat > "${DATA}/purpur.yml" << 'EOF'
settings:
  allow-end: true
purpur:
  tick-limiter:
    enabled: true
EOF
    ;;


  # ============================================================
  # Fabric
  # ============================================================
  fabric)
    log "Fabric: Mods generate their own configs → skipping."
    ;;


  # ============================================================
  # Forge / NeoForge
  # ============================================================
  forge | neoforge)
    log "Forge/NeoForge: Mod configs handled automatically → skipping."
    ;;


  # ============================================================
  # BungeeCord
  # ============================================================
  bungeecord)
    log "Generating BungeeCord config.yml..."

    cat > "${DATA}/config.yml" << 'EOF'
server_connect_timeout: 5000
listeners:
  - query_port: 25577
    motd: "A Minecraft Proxy"
    tab_list: GLOBAL_PING
    query_enabled: true
    proxy_protocol: false
    forced_hosts:
      example.com: lobby
    ping_passthrough: false
    priorities:
      - lobby
    bind_local_address: true
    host: 0.0.0.0:25577
    max_players: 200
    force_default_server: true

servers:
  lobby:
    motd: "Lobby Server"
    address: lobby:25565
    restricted: false

online_mode: true
log_commands: false
disabled_commands:
  - disabledcommandexample
EOF
    ;;


  # ============================================================
  # Waterfall
  # ============================================================
  waterfall)
    log "Generating Waterfall config.yml..."

    cat > "${DATA}/config.yml" << 'EOF'
listeners:
  - host: 0.0.0.0:25577
    max_players: 200
    tab_list: GLOBAL_PING
    motd: "Waterfall Proxy"
    force_default_server: true
servers:
  lobby:
    address: lobby:25565
    restricted: false
forge_support: false
online_mode: true
EOF
    ;;


  # ============================================================
  # Velocity
  # ============================================================
  velocity)
    log "Generating velocity.toml..."

    cat > "${DATA}/velocity.toml" << 'EOF'
bind = "0.0.0.0:25577"
motd = "Velocity Proxy"
show-max-players = 200

[servers]
lobby = "lobby:25565"

try = ["lobby"]

[forced-hosts]
"example.com" = ["lobby"]

online-mode = true
player-info-forwarding-mode = "velocity"
EOF
    ;;


  # ============================================================
  # Vanilla（設定なし）
  # ============================================================
  vanilla)
    log "Vanilla: No additional config required."
    ;;


  # ============================================================
  # Unknown
  # ============================================================
  *)
    log "Unknown TYPE='${TYPE}', no TYPE config generated."
    ;;
esac

log "TYPE=${TYPE} configuration generation complete."
