#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# Log function to track script execution
# ------------------------------------------------------------
log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$1] $2"
}

# ------------------------------------------------------------
# Set defaults if environment variables are not provided
# ------------------------------------------------------------
: "${SERVER_PORT:=25565}"
: "${SERVER_IP:=""}"
: "${ONLINE_MODE:=true}"
: "${PREVENT_PROXY_CONNECTIONS:=false}"
: "${USE_NATIVE_TRANSPORT:=true}"
: "${ENABLE_STATUS:=true}"
: "${ENABLE_QUERY:=false}"
: "${QUERY_PORT:=25565}"

: "${ENABLE_RCON:=false}"
: "${RCON_PORT:=25575}"
: "${RCON_PASSWORD:="change_this_password"}"
: "${RCON_MAX_CONNECTIONS:=5}"
: "${RCON_TIMEOUT:=60}"

: "${MAX_PLAYERS:=20}"
: "${DIFFICULTY:=easy}"
: "${MODE:=survival}"
: "${HARDCORE:=false}"
: "${PVP:=true}"
: "${ALLOW_FLIGHT:=false}"
: "${FORCE_GAMEMODE:=false}"
: "${SPAWN_PROTECTION:=16}"

: "${LEVEL:=world}"
: "${LEVEL_SEED:=""}"
: "${LEVEL_TYPE:=minecraft:normal}"
: "${GENERATE_STRUCTURES:=true}"
: "${ALLOW_NETHER:=true}"
: "${MAX_WORLD_SIZE:=29999984}"

: "${VIEW_DISTANCE:=10}"
: "${SIMULATION_DISTANCE:=10}"
: "${ENTITY_BROADCAST_RANGE_PERCENTAGE:=100}"
: "${NETWORK_COMPRESSION_THRESHOLD:=256}"
: "${SYNC_CHUNK_WRITES:=true}"

: "${MOTD:="A Minecraft Server"}"
: "${WHITE_LIST:=false}"
: "${ENFORCE_WHITELIST:=false}"
: "${ENFORCE_SECURE_PROFILE:=true}"

# ------------------------------------------------------------
# Check if the server properties template exists
# ------------------------------------------------------------
TEMPLATE_PATH="/opt/mc/base/server.properties.base"
OUTPUT_PATH="/data/server.properties"

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  log ERROR "server.properties.template does not exist at ${TEMPLATE_PATH}"
  exit 1
fi

log INFO "Rendering server.properties from base.env and environment variables"

# ------------------------------------------------------------
# Render server.properties using sed and environment variables
# ------------------------------------------------------------
# Replace placeholders in the template with actual values from environment variables
sed -e "s/\${SERVER_PORT}/${SERVER_PORT}/g" \
    -e "s/\${SERVER_IP}/${SERVER_IP}/g" \
    -e "s/\${ONLINE_MODE}/${ONLINE_MODE}/g" \
    -e "s/\${PREVENT_PROXY_CONNECTIONS}/${PREVENT_PROXY_CONNECTIONS}/g" \
    -e "s/\${USE_NATIVE_TRANSPORT}/${USE_NATIVE_TRANSPORT}/g" \
    -e "s/\${ENABLE_STATUS}/${ENABLE_STATUS}/g" \
    -e "s/\${ENABLE_QUERY}/${ENABLE_QUERY}/g" \
    -e "s/\${QUERY_PORT}/${QUERY_PORT}/g" \
    -e "s/\${ENABLE_RCON}/${ENABLE_RCON}/g" \
    -e "s/\${RCON_PORT}/${RCON_PORT}/g" \
    -e "s/\${RCON_PASSWORD}/${RCON_PASSWORD}/g" \
    -e "s/\${RCON_MAX_CONNECTIONS}/${RCON_MAX_CONNECTIONS}/g" \
    -e "s/\${RCON_TIMEOUT}/${RCON_TIMEOUT}/g" \
    -e "s/\${MAX_PLAYERS}/${MAX_PLAYERS}/g" \
    -e "s/\${DIFFICULTY}/${DIFFICULTY}/g" \
    -e "s/\${MODE}/${MODE}/g" \
    -e "s/\${HARDCORE}/${HARDCORE}/g" \
    -e "s/\${PVP}/${PVP}/g" \
    -e "s/\${ALLOW_FLIGHT}/${ALLOW_FLIGHT}/g" \
    -e "s/\${FORCE_GAMEMODE}/${FORCE_GAMEMODE}/g" \
    -e "s/\${SPAWN_PROTECTION}/${SPAWN_PROTECTION}/g" \
    -e "s/\${LEVEL}/${LEVEL}/g" \
    -e "s/\${LEVEL_SEED}/${LEVEL_SEED}/g" \
    -e "s/\${LEVEL_TYPE}/${LEVEL_TYPE}/g" \
    -e "s/\${GENERATE_STRUCTURES}/${GENERATE_STRUCTURES}/g" \
    -e "s/\${ALLOW_NETHER}/${ALLOW_NETHER}/g" \
    -e "s/\${MAX_WORLD_SIZE}/${MAX_WORLD_SIZE}/g" \
    -e "s/\${VIEW_DISTANCE}/${VIEW_DISTANCE}/g" \
    -e "s/\${SIMULATION_DISTANCE}/${SIMULATION_DISTANCE}/g" \
    -e "s/\${ENTITY_BROADCAST_RANGE_PERCENTAGE}/${ENTITY_BROADCAST_RANGE_PERCENTAGE}/g" \
    -e "s/\${NETWORK_COMPRESSION_THRESHOLD}/${NETWORK_COMPRESSION_THRESHOLD}/g" \
    -e "s/\${SYNC_CHUNK_WRITES}/${SYNC_CHUNK_WRITES}/g" \
    -e "s/\${MOTD}/${MOTD}/g" \
    -e "s/\${WHITE_LIST}/${WHITE_LIST}/g" \
    -e "s/\${ENFORCE_WHITELIST}/${ENFORCE_WHITELIST}/g" \
    -e "s/\${ENFORCE_SECURE_PROFILE}/${ENFORCE_SECURE_PROFILE}/g" \
    "$TEMPLATE_PATH" > "$OUTPUT_PATH"

log INFO "server.properties generated successfully at ${OUTPUT_PATH}"

exit 0
