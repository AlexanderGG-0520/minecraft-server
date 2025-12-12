#!/bin/bash
set -euo pipefail

OUT="/data/server.jar"

# 既にあれば何もしない
if [[ -f "$OUT" ]]; then
  exit 0
fi

echo "[detect_waterfall] Resolving latest Waterfall build..."

# 最新バージョン取得
VERSION="$(curl -fsSL https://api.papermc.io/v2/projects/waterfall \
  | jq -r '.versions[-1]')"

# 最新ビルド取得
BUILD="$(curl -fsSL https://api.papermc.io/v2/projects/waterfall/versions/${VERSION} \
  | jq -r '.builds[-1]')"

URL="https://api.papermc.io/v2/projects/waterfall/versions/${VERSION}/builds/${BUILD}/downloads/waterfall-${VERSION}-${BUILD}.jar"

echo "[detect_waterfall] Downloading Waterfall ${VERSION} build ${BUILD}"
curl -fL "$URL" -o "$OUT"

echo "[detect_waterfall] Waterfall server.jar ready"
