#!/usr/bin/env bash
set -euo pipefail

cat > "$MC_ARGS_FILE" <<EOF
--port
${SERVER_PORT}
EOF

if [[ "${ENABLE_GUI}" == "false" ]]; then
  echo "nogui" >> "$MC_ARGS_FILE"
fi
