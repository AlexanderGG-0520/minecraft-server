#!/bin/bash
set -euo pipefail

OUT=/data/server.jar
[[ -f "$OUT" ]] && exit 0

VER="$(curl -fsSL https://api.papermc.io/v2/projects/velocity \
  | jq -r '.versions[-1]')"
BUILD="$(curl -fsSL https://api.papermc.io/v2/projects/velocity/versions/${VER} \
  | jq -r '.builds[-1]')"

curl -fL "https://api.papermc.io/v2/projects/velocity/versions/${VER}/builds/${BUILD}/downloads/velocity-${VER}-${BUILD}.jar" \
  -o "$OUT"
