#!/bin/bash
set -euo pipefail

DATA=/data

IFS=',' read -ra OPS_ARR <<< "${OPS:-}"
IFS=',' read -ra WL_ARR  <<< "${WHITELIST:-}"

add_player() {
  local name="$1" file="$2"
  jq --arg n "$name" '. + [{"uuid":"00000000-0000-0000-0000-000000000000","name":$n}]' \
    "$file" > /tmp/t.json && mv /tmp/t.json "$file"
}

[[ ! -f "$DATA/ops.json" ]] && echo "[]" > "$DATA/ops.json"
[[ ! -f "$DATA/whitelist.json" ]] && echo "[]" > "$DATA/whitelist.json"

for p in "${OPS_ARR[@]}"; do
  add_player "$p" "$DATA/ops.json"
done

for p in "${WL_ARR[@]}"; do
  add_player "$p" "$DATA/whitelist.json"
done
