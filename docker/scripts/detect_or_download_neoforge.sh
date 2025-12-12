#!/bin/bash
set -euo pipefail

OUT=/data/server.jar
MC="${VERSION:?VERSION required}"

[[ -f "$OUT" ]] && exit 0

META="$(curl -fsSL https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml)"
VER="$(echo "$META" | xmllint --xpath 'string(//versioning/latest)' -)"

curl -fL "https://maven.neoforged.net/releases/net/neoforged/neoforge/${VER}/neoforge-${VER}-installer.jar" \
  -o /tmp/installer.jar

java -jar /tmp/installer.jar --installServer /data
mv /data/neoforge-*.jar "$OUT"
