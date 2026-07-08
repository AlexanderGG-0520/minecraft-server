#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"

cat > "$tmp/bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

timeout_duration="$1"
shift

if [[ "${1:-}" == "--" ]]; then
  shift
fi

printf '%s %s\n' "$timeout_duration" "$*" >> "$TIMEOUT_LOG"
"$@"
EOF

cat > "$tmp/bin/java" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

props="$(dirname "$2")/server.properties"
cat > "$props" <<'PROPS'
enforce-secure-profile=true
online-mode=true
server-port=25566
server-ip=
motd=A Minecraft Server
gamemode=survival
enable-rcon=false
PROPS
EOF

chmod +x "$tmp/bin/timeout" "$tmp/bin/java"
PATH="$tmp/bin:$PATH"
TIMEOUT_LOG="$tmp/timeout.log"
export TIMEOUT_LOG

DATA_DIR="$tmp/data"
TYPE=paper
EULA=true
APPLY_SERVER_PROPERTIES_DIFF=true
ENFORCE_SECURE_PROFILE=false
ONLINE_MODE=false
SERVER_PORT=25565
SERVER_IP=0.0.0.0
MOTD="Env MOTD"
GAMEMODE=creative
ENABLE_RCON=false
__SOURCED=1
export PATH DATA_DIR TYPE EULA APPLY_SERVER_PROPERTIES_DIFF
export ENFORCE_SECURE_PROFILE ONLINE_MODE SERVER_PORT SERVER_IP MOTD GAMEMODE ENABLE_RCON
export __SOURCED

source ./entrypoint.sh

mkdir -p "$DATA_DIR"
touch "$DATA_DIR/server.jar"

output="$(install_server_properties 2>&1)"
printf '%s\n' "$output" | grep -F "server.properties not found, generating via bootstrap" >/dev/null
printf '%s\n' "$output" | grep -F "server.properties bootstrap timeout: 15s" >/dev/null
printf '%s\n' "$output" | grep -F "server.properties successfully bootstrapped" >/dev/null
printf '%s\n' "$output" | grep -F "server.properties ready, applying env diff" >/dev/null
printf '%s\n' "$output" | grep -F "server.properties diff apply completed" >/dev/null
grep -F "15s java -jar $DATA_DIR/server.jar nogui" "$TIMEOUT_LOG" >/dev/null

grep -Fx "enforce-secure-profile=false" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "online-mode=false" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "server-port=25565" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "server-ip=0.0.0.0" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "motd=Env MOTD" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "gamemode=creative" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "enable-rcon=false" "$DATA_DIR/server.properties" >/dev/null

DATA_DIR="$tmp/diff-disabled"
APPLY_SERVER_PROPERTIES_DIFF=false
export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF
mkdir -p "$DATA_DIR"
touch "$DATA_DIR/server.jar"

install_server_properties >/dev/null 2>&1
grep -Fx "enforce-secure-profile=true" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "online-mode=true" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "server-port=25566" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "server-ip=" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "enable-rcon=false" "$DATA_DIR/server.properties" >/dev/null

DATA_DIR="$tmp/existing"
APPLY_SERVER_PROPERTIES_DIFF=true
export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF
mkdir -p "$DATA_DIR"
cat > "$DATA_DIR/server.properties" <<'PROPS'
enforce-secure-profile=true
online-mode=true
server-port=25566
server-ip=
enable-rcon=false
PROPS

install_server_properties >/dev/null 2>&1
grep -Fx "enforce-secure-profile=false" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "online-mode=false" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "server-port=25565" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "server-ip=0.0.0.0" "$DATA_DIR/server.properties" >/dev/null

DATA_DIR="$tmp/rcon"
APPLY_SERVER_PROPERTIES_DIFF=false
ENABLE_RCON=true
RCON_PORT=25575
RCON_PASSWORD=secret
export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF ENABLE_RCON RCON_PORT RCON_PASSWORD
mkdir -p "$DATA_DIR"
touch "$DATA_DIR/server.jar"

install_server_properties >/dev/null 2>&1
grep -Fx "enforce-secure-profile=true" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "enable-rcon=true" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "rcon.port=25575" "$DATA_DIR/server.properties" >/dev/null
grep -Fx "rcon.password=secret" "$DATA_DIR/server.properties" >/dev/null

DATA_DIR="$tmp/forge"
TYPE=forge
unset SERVER_PROPERTIES_BOOTSTRAP_TIMEOUT
export DATA_DIR TYPE
mkdir -p "$DATA_DIR"
cat > "$DATA_DIR/run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat > "$(dirname "$0")/server.properties" <<'PROPS'
enable-rcon=false
PROPS
EOF
chmod +x "$DATA_DIR/run.sh"

output="$(bootstrap_server_properties 2>&1)"
printf '%s\n' "$output" | grep -F "server.properties bootstrap timeout: 90s" >/dev/null
grep -F "90s $DATA_DIR/run.sh nogui" "$TIMEOUT_LOG" >/dev/null

DATA_DIR="$tmp/override"
TYPE=paper
SERVER_PROPERTIES_BOOTSTRAP_TIMEOUT=3s
export DATA_DIR TYPE SERVER_PROPERTIES_BOOTSTRAP_TIMEOUT
mkdir -p "$DATA_DIR"
touch "$DATA_DIR/server.jar"

output="$(bootstrap_server_properties 2>&1)"
printf '%s\n' "$output" | grep -F "server.properties bootstrap timeout: 3s" >/dev/null
grep -F "3s java -jar $DATA_DIR/server.jar nogui" "$TIMEOUT_LOG" >/dev/null
