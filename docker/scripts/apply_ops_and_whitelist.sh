#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# Log function to track script execution
# ------------------------------------------------------------
log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$1] $2"
}

# ------------------------------------------------------------
# Get UUID from Mojang API for a player
# ------------------------------------------------------------
get_uuid() {
  local player_name=$1
  # Minecraft Profile API から UUID を取得
  uuid=$(curl -s "https://api.mojang.com/users/profiles/minecraft/$player_name" | jq -r '.id')

  # If UUID is empty or invalid, log error and exit
  if [[ -z "$uuid" || "$uuid" == "null" ]]; then
    log ERROR "Failed to fetch UUID for player: $player_name"
    exit 1
  fi
  echo "$uuid"
}

# ------------------------------------------------------------
# Add players to ops.json and whitelist.json based on environment variables
# ------------------------------------------------------------
add_players() {
  local json_file=$1
  local player_list=$2
  local permission_level=$3

  log INFO "Adding players to $json_file"

  # If the file doesn't exist or is empty, create it with an empty array
  if [[ ! -f "$json_file" || ! -s "$json_file" ]]; then
    echo "[]" > "$json_file"
  fi

  # Iterate through the player list
  for player in $(echo "$player_list" | tr "," "\n"); do
    # Get the UUID for the player
    uuid=$(get_uuid "$player")

    # Check if player already exists in the JSON (using UUID)
    if ! jq -e ".[] | select(.uuid == \"$uuid\")" "$json_file" > /dev/null; then
      log INFO "Adding player $player ($uuid) to $json_file with permission level $permission_level"
      
      # Add player to the JSON file
      jq ". += [{\"name\": \"$player\", \"uuid\": \"$uuid\", \"level\": \"$permission_level\", \"banned\": false}]" "$json_file" > temp.json && mv temp.json "$json_file"
    else
      log INFO "Player $player ($uuid) already exists in $json_file"
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
