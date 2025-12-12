#!/usr/bin/env bash
set -euo pipefail

# 基本の server.properties をテンプレートとして指定
TEMPLATE_PATH="/opt/mc/base/server.properties.base"
OUTPUT_PATH="/data/server.properties"

# server.properties を生成
log INFO "Generating server.properties..."

# 基本のテンプレートに環境変数で置き換える
cat "$TEMPLATE_PATH" | while read -r line; do
  # 各行に対して環境変数が設定されていれば、置き換えを行う
  echo "$line" | envsubst
done > "$OUTPUT_PATH"

log INFO "server.properties generated successfully at $OUTPUT_PATH"
