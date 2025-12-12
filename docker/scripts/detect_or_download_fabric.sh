#!/bin/bash
set -euo pipefail

OUT=/data/server.jar
MC="${VERSION:-latest}"
LOADER="${FABRIC_LOADER:-latest}"

[[ -f "$OUT" ]] && exit 0

if [[ "$MC" == "latest" ]]; then
  MC="$(curl -fsSL https://meta.fabricmc.net/v2/versions/game \
    | jq -r '.[0].version')"
fi

if [[ "$LOADER" == "latest" ]]; then
  LOADER="$(curl -fsSL https://meta.fabricmc.net/v2/versions/loader \
    | jq -r '.[0].version')"
fi

URL="https://meta.fabricmc.net/v2/versions/loader/${MC}/${LOADER}/1.0.1/server/jar"
curl -fL "$URL" -o "$OUT"
