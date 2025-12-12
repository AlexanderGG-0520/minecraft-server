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