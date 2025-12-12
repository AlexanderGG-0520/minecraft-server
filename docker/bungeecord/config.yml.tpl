server_connect_timeout: 5000
listeners:
  - query_port: {{PORT}}
    motd: "{{MOTD}}"
    tab_list: {{TABLIST}}
    query_enabled: true
    proxy_protocol: false
    forced_hosts:
      {{FORCED_HOST}}: {{TARGET_SERVER}}
    ping_passthrough: false
    priorities:
      - {{LOBBY_NAME}}
    bind_local_address: true
    host: {{HOST}}:{{PORT}}
    max_players: {{MAX_PLAYERS}}
    tab_size: 60
    force_default_server: {{LOBBY_FORCED}}
timeout: 30000
connection_throttle_limit: 3
prevent_proxy_connections: false

servers:
  {{LOBBY_NAME}}:
    motd: "Lobby Server"
    address: {{LOBBY_ADDR}}
    restricted: false

online_mode: {{ONLINE_MODE}}
log_commands: {{LOG_COMMANDS}}
disabled_commands:
  - disabledcommandexample
network_compression_threshold: 256
stats: {{DISABLE_STATS}}
connection_throttle: 4000
