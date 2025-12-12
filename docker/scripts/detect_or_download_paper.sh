#!/bin/bash
set -euo pipefail

OUT=/data/server.jar
MC="${VERSION:-latest}"

[[ -f "$OUT" ]] && exit 0

if [[ "$MC" == "latest" ]]; then
  MC="$(curl -fsSL https://api.papermc.io/v2/projects/paper \
    | jq -r '.versions[-1]')"
fi

BUILD="$(curl -fsSL https://api.papermc.io/v2/projects/paper/versions/${MC} \
  | jq -r '.builds[-1]')"

URL="https://api.papermc.io/v2/projects/paper/versions/${MC}/builds/${BUILD}/downloads/paper-${MC}-${BUILD}.jar"
curl -fL "$URL" -o "$OUT"
