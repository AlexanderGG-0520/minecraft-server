#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/jvm_args.sh

DATA_DIR="$tmp/data"
JVM_ARGS_FILE="$tmp/custom/custom.jvm.args"
mkdir -p "$DATA_DIR" "$(dirname "$JVM_ARGS_FILE")"

unset_jvm_env() {
  unset JVM_XMS
  unset JVM_XMX
  unset JVM_GC
  unset JVM_USE_CONTAINER_SUPPORT
  unset JVM_EXTRA_ARGS
}

assert_file_contains() {
  local file="$1"
  local text="$2"

  grep -F -- "$text" "$file" >/dev/null
}

unset_jvm_env
JVM_XMS=256M
JVM_XMX=1G
JVM_GC=ZGC
JVM_USE_CONTAINER_SUPPORT=false
JVM_EXTRA_ARGS="-Dexample=true"

install_jvm_args >/dev/null

test -f "$JVM_ARGS_FILE"
test ! -e "$DATA_DIR/jvm.args"

expected="$tmp/expected.jvm.args"
printf '%s\n' \
  "-Xms256M" \
  "-Xmx1G" \
  "-XX:+UseZGC" \
  "-Dexample=true" \
  > "$expected"

cmp "$expected" "$JVM_ARGS_FILE"

# Existing file with non-exported JVM variables must not be clobbered.
printf '%s\n' "# custom" > "$JVM_ARGS_FILE"
unset_jvm_env
JVM_XMX=4G
install_jvm_args >/dev/null
assert_file_contains "$JVM_ARGS_FILE" "# custom"

# Existing file with exported JVM variables must be regenerated.
printf '%s\n' "# custom" > "$JVM_ARGS_FILE"
unset_jvm_env
export JVM_XMX=2G
install_jvm_args >/dev/null
assert_file_contains "$JVM_ARGS_FILE" "-Xmx2G"
if grep -F -- "# custom" "$JVM_ARGS_FILE" >/dev/null; then
  exit 1
fi

# Non-exported internal-default-equivalent values must not clobber hand-written args.
printf '%s\n' "# manual" > "$JVM_ARGS_FILE"
unset_jvm_env
JVM_XMS=512M
JVM_XMX=512M
JVM_GC=G1
JVM_USE_CONTAINER_SUPPORT=true
JVM_EXTRA_ARGS=
install_jvm_args >/dev/null
assert_file_contains "$JVM_ARGS_FILE" "# manual"
