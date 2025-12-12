#!/bin/bash
set -euo pipefail

OUT=/data/server.jar
[[ -f "$OUT" ]] && exit 0

curl -fL https://ci.md-5.net/job/BungeeCord/lastSuccessfulBuild/artifact/bootstrap/target/BungeeCord.jar \
  -o "$OUT"
