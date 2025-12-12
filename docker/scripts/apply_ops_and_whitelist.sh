#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# Log function to track script execution
# ------------------------------------------------------------
log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$1] $2"
}

# ------------------------------------------------------------
# Add players to ops.json and whitelist.json based on environment variables
# ------------------------------------------------------------
add_players() {
  local json_file=$1
  local player_list=$2
  local permission_level=$3

  log INFO "Adding players to $json_file"

  # If the file doesn't exist, create it
  if [[ ! -f "$json_file" ]]; then
    echo "[]" > "$json_file"
  fi

  for player in $(echo "$player_list" | tr "," "\n"); do
    # Check if player already exists in the JSON
    if ! jq -e ".[] | select(.name == \"$player\")" "$json_file" > /dev/null; then
      log INFO "Adding player $player to $json_file with permission level $permission_level"
      jq ". += [{\"name\": \"$player\", \"uuid\": \"$(uuidgen)\", \"level\": \"$permission_level\", \"banned\": false}]" "$json_file" > temp.json && mv temp.json "$json_file"
    else
      log INFO "Player $player already exists in $json_file"
    fi
  done
}

# ------------------------------------------------------------
# Add OPS if OPS variable is set
# ------------------------------------------------------------
if [[ -n "${OPS:-}" ]]; then
  add_players "/data/ops.json" "$OPS" "4"
fi

# ------------------------------------------------------------
# Add players to whitelist if WHITELIST variable is set
# ------------------------------------------------------------
if [[ -n "${WHITELIST:-}" ]]; then
  add_players "/data/whitelist.json" "$WHITELIST" "4"
fi

log INFO "Player addition completed"
