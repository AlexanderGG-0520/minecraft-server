#!/usr/bin/env bash
set -euo pipefail

MC_ARGS_FILE="/data/mc.args"
: "${SERVER_PORT:=25565}"
: "${ENABLE_GUI:=false}"

cat > "$MC_ARGS_FILE" <<EOF
--port
${SERVER_PORT}
EOF

if [[ "${ENABLE_GUI}" == "false" ]]; then
  echo "nogui" >> "$MC_ARGS_FILE"
fi
