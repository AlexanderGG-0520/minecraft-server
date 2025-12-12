#!/bin/bash
set -euo pipefail

OUT=/data/server.jar
MC="${VERSION:?VERSION required}"
FORGE_VERSION="${FORGE_VERSION:-latest}"

[[ -f "$OUT" ]] && exit 0

if [[ "$FORGE_VERSION" == "latest" ]]; then
  FORGE_VERSION="$(curl -fsSL https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json \
    | jq -r --arg mc "$MC" '.promos[$mc+"-recommended"]')"
fi

INSTALLER="forge-${MC}-${FORGE_VERSION}-installer.jar"

curl -fL "https://maven.minecraftforge.net/net/minecraftforge/forge/${MC}-${FORGE_VERSION}/${INSTALLER}" -o /tmp/installer.jar
java -jar /tmp/installer.jar --installServer /data
mv /data/forge-*.jar "$OUT"
