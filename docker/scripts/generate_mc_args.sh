#!/usr/bin/env bash
set -euo pipefail

MC_ARGS_FILE="/data/mc.args"

# --- 必須だけど値は決めない ---
: "${SERVER_PORT:?SERVER_PORT must be set (e.g. 25565)}"
: "${ENABLE_GUI:=false}"

cat > "$MC_ARGS_FILE" <<EOF
--port
${SERVER_PORT}
EOF

if [[ "${ENABLE_GUI}" == "false" ]]; then
  echo "nogui" >> "$MC_ARGS_FILE"
fi
