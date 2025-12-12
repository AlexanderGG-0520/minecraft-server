#!/bin/bash
set -euo pipefail

OUT=/data/server.jar
MC="${VERSION:-latest}"

[[ -f "$OUT" ]] && exit 0

if [[ "$MC" == "latest" ]]; then
  MC="$(curl -fsSL https://api.purpurmc.org/v2/purpur \
    | jq -r '.versions[-1]')"
fi

BUILD="$(curl -fsSL https://api.purpurmc.org/v2/purpur/${MC} \
  | jq -r '.builds.latest')"

curl -fL "https://api.purpurmc.org/v2/purpur/${MC}/${BUILD}/download" -o "$OUT"
