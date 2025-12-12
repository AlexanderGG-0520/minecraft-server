#!/usr/bin/env bash

# プレイヤー名からUUIDを取得するための関数
get_uuid() {
  local player_name=$1
  # Minecraft Profile API から UUID を取得
  uuid=$(curl -s "https://api.mojang.com/users/profiles/minecraft/${player_name}" | jq -r '.id')
  echo $uuid
}

# OPSの処理
for player in $(echo "$OPS" | sed "s/,/ /g")
do
  uuid=$(get_uuid "$player")
  echo "Adding player $player ($uuid) to /data/ops.json"
  jq ". += [{\"uuid\": \"$uuid\", \"name\": \"$player\", \"level\": 4, \"bypassesPlayerLimit\": false}]" /data/ops.json > /data/ops.json.tmp && mv /data/ops.json.tmp /data/ops.json
done

# WHITELISTの処理
for player in $(echo "$WHITELIST" | sed "s/,/ /g")
do
  uuid=$(get_uuid "$player")
  echo "Adding player $player ($uuid) to /data/whitelist.json"
  jq ". += [{\"uuid\": \"$uuid\", \"name\": \"$player\", \"bypassesPlayerLimit\": false}]" /data/whitelist.json > /data/whitelist.json.tmp && mv /data/whitelist.json.tmp /data/whitelist.json
done
