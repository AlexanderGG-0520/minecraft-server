#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

DATA_DIR="$tmp/data"
APPLY_SERVER_PROPERTIES_DIFF=true
MOTD='Env MOTD / path: {text:hi} & pipes | colors'
SERVER_PORT=25570
SERVER_IP=
QUERY_PORT=25571
RCON_PASSWORD='rcon-secret-value'
MANAGEMENT_SERVER_HOST=0.0.0.0
MANAGEMENT_SERVER_SECRET='management-secret-value'
MANAGEMENT_SERVER_TLS_KEYSTORE_PASSWORD='keystore-secret-value'
REQUIRE_RESOURCE_PACK=true
RESOURCE_PACK='https://example.com/resource pack.zip'
VIEW_DISTANCE=12
SIMULATION_DISTANCE=8
WHITE_LIST=true
ACCEPTS_TRANSFERS=true
export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF MOTD SERVER_PORT SERVER_IP QUERY_PORT RCON_PASSWORD
export MANAGEMENT_SERVER_HOST MANAGEMENT_SERVER_SECRET MANAGEMENT_SERVER_TLS_KEYSTORE_PASSWORD
export REQUIRE_RESOURCE_PACK RESOURCE_PACK VIEW_DISTANCE SIMULATION_DISTANCE WHITE_LIST ACCEPTS_TRANSFERS

source ./scripts/lib/logging.sh
source ./scripts/lib/runtime.sh
source ./scripts/lib/server_properties.sh

mkdir -p "$DATA_DIR"
cat > "$DATA_DIR/server.properties" <<'PROPS'
# Existing comments should stay in place.
motd=Old MOTD
server-port=25565
server-ip=127.0.0.1
query.port=25565
difficulty=hard
management-server-host=127.0.0.1
white-list=false
custom-key=custom-value
PROPS

output="$(apply_server_properties_diff 2>&1)"

grep -Fx '# Existing comments should stay in place.' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'motd=Env MOTD / path: {text:hi} & pipes | colors' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'server-port=25570' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'server-ip=' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'query.port=25571' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'difficulty=hard' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'custom-key=custom-value' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'rcon.password=rcon-secret-value' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'management-server-host=0.0.0.0' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'management-server-secret=management-secret-value' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'management-server-tls-keystore-password=keystore-secret-value' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'require-resource-pack=true' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'resource-pack=https://example.com/resource pack.zip' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'view-distance=12' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'simulation-distance=8' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'white-list=true' "$DATA_DIR/server.properties" >/dev/null
grep -Fx 'accepts-transfers=true' "$DATA_DIR/server.properties" >/dev/null

printf '%s\n' "$output" | grep -F 'rcon-secret-value' && exit 1
printf '%s\n' "$output" | grep -F 'management-secret-value' && exit 1
printf '%s\n' "$output" | grep -F 'keystore-secret-value' && exit 1
printf '%s\n' "$output" | grep -F 'rcon.password=<masked>' >/dev/null
printf '%s\n' "$output" | grep -F 'management-server-secret=<masked>' >/dev/null
printf '%s\n' "$output" | grep -F 'management-server-tls-keystore-password=<masked>' >/dev/null
