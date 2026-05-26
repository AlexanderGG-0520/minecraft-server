#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/jvm_args.sh

DATA_DIR="$tmp/data"
JVM_ARGS_FILE="$tmp/custom/custom.jvm.args"
JVM_XMS=256M
JVM_XMX=1G
JVM_GC=ZGC
JVM_USE_CONTAINER_SUPPORT=false
JVM_EXTRA_ARGS="-Dexample=true"
mkdir -p "$DATA_DIR" "$(dirname "$JVM_ARGS_FILE")"

install_jvm_args >/dev/null

test -f "$JVM_ARGS_FILE"
test ! -e "$DATA_DIR/jvm.args"

expected="$tmp/expected.jvm.args"
cat > "$expected" <<'EOF'
-Xms256M
-Xmx1G
-XX:+UseZGC
-Dexample=true
EOF

cmp "$expected" "$JVM_ARGS_FILE"

install_jvm_args >/dev/null
cmp "$expected" "$JVM_ARGS_FILE"
