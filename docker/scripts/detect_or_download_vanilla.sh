#!/bin/bash
set -euo pipefail

OUT=/data/server.jar
VERSION="${VERSION:-latest}"

[[ -f "$OUT" ]] && exit 0

if [[ "$VERSION" == "latest" ]]; then
  VERSION="$(curl -fsSL https://launchermeta.mojang.com/mc/game/version_manifest.json \
    | jq -r '.latest.release')"
fi

META_URL="$(curl -fsSL https://launchermeta.mojang.com/mc/game/version_manifest.json \
  | jq -r --arg v "$VERSION" '.versions[] | select(.id==$v) | .url')"

JAR_URL="$(curl -fsSL "$META_URL" | jq -r '.downloads.server.url')"

curl -fL "$JAR_URL" -o "$OUT"
