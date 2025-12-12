#!/bin/bash

# プレイヤー名を環境変数から取得（OPSまたはWHITELIST）
OPS=${OPS:-}
WHITELIST=${WHITELIST:-}

add_player_to_json() {
    local player_name=$1
    local json_file=$2

    # Mojang APIを使ってプレイヤーのUUIDを取得
    player_uuid=$(curl -s "https://api.mojang.com/users/profiles/minecraft/$player_name" | jq -r '.id')

    if [ "$player_uuid" == "null" ]; then
        echo "Error: Could not find UUID for player $player_name"
        return 1
    fi

    # プレイヤーをops.jsonまたはwhitelist.jsonに追加
    echo "Adding $player_name ($player_uuid) to $json_file"
    
    # ops.jsonまたはwhitelist.jsonにプレイヤーを追加
    jq ". += [{\"uuid\": \"$player_uuid\", \"name\": \"$player_name\", \"level\": 4}]" "$json_file" > temp.json && mv temp.json "$json_file"
}

# OPSのプレイヤーをops.jsonに追加
if [ -n "$OPS" ]; then
    for player in $(echo "$OPS" | tr "," "\n"); do
        add_player_to_json "$player" "/data/ops.json"
    done
fi

# WHITELISTのプレイヤーをwhitelist.jsonに追加
if [ -n "$WHITELIST" ]; then
    for player in $(echo "$WHITELIST" | tr "," "\n"); do
        add_player_to_json "$player" "/data/whitelist.json"
    done
fi

echo "OPS and WHITELIST processing completed"
