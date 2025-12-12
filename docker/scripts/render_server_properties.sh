#!/usr/bin/env bash

# プレイヤー名からUUIDを取得するための関数
get_uuid() {
  local player_name=$1
  # Minecraft Profile API から UUID を取得
  uuid=$(curl -s -w "%{http_code}" -o /tmp/minecraft_response.json "https://api.mojang.com/users/profiles/minecraft/${player_name}")
  
  # レスポンスコードを確認
  if [[ $? -ne 0 || $(tail -n 1 /tmp/minecraft_response.json) -ne 200 ]]; then
    echo "Error: Unable to fetch UUID for player '${player_name}'."
    return 1
  fi

  # UUIDを抽出
  uuid=$(jq -r '.id' /tmp/minecraft_response.json)

  # UUIDが取得できたか確認
  if [[ "$uuid" == "null" || -z "$uuid" ]]; then
    echo "Error: Invalid player name or no UUID found for '${player_name}'."
    return 1
  fi

  echo $uuid
}

# OPSの処理
for player in $(echo "$OPS" | sed "s/,/ /g")
do
  echo "Processing player: $player"
  uuid=$(get_uuid "$player")
  echo "UUID for player $player: $uuid"
  echo "Adding player $player to ops.json"
  jq ". += [{\"uuid\": \"$uuid\", \"name\": \"$player\", \"level\": 4, \"bypassesPlayerLimit\": false}]" /data/ops.json > /data/ops.json.tmp && mv /data/ops.json.tmp /data/ops.json
done


# WHITELISTの処理
for player in $(echo "$WHITELIST" | sed "s/,/ /g")
do
  echo "Processing whitelist player: $player"
  uuid=$(get_uuid "$player")
  echo "UUID for player $player: $uuid"
  echo "Adding player $player to whitelist.json"
  jq ". += [{\"uuid\": \"$uuid\", \"name\": \"$player\", \"bypassesPlayerLimit\": false}]" /data/whitelist.json > /data/whitelist.json.tmp && mv /data/whitelist.json.tmp /data/whitelist.json
done

