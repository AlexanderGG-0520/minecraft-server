#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh
source ./scripts/lib/s3_client.sh
source ./scripts/lib/content_assets.sh

configure_calls="$tmp/configure-calls"
aws_calls="$tmp/aws-calls"
: > "$configure_calls"
: > "$aws_calls"

configure_s3_client() {
  printf '%s\n' "$1" >> "$configure_calls"
}

aws() {
  printf '%s\n' "$*" >> "$aws_calls"
  case "$1 $2" in
    "s3 sync")
      mkdir -p "$4"
      printf '%s\n' pack > "$4/example.zip"
      ;;
    *)
      return 99
      ;;
  esac
}

reset_calls() {
  : > "$configure_calls"
  : > "$aws_calls"
}

assert_no_s3_calls() {
  test ! -s "$configure_calls"
  test ! -s "$aws_calls"
}

DATA_DIR="$tmp/data"
mkdir -p "$DATA_DIR"

INPUT_RESOURCEPACKS_DIR="$tmp/input-resourcepacks"
RESOURCEPACKS_ENABLED=true
RESOURCEPACKS_S3_BUCKET=bucket
RESOURCEPACKS_S3_PREFIX=resourcepacks
unset RESOURCEPACKS_SYNC_ONCE
unset RESOURCEPACKS_REMOVE_EXTRA
reset_calls
install_resourcepacks
test "$(cat "$configure_calls")" = "resourcepacks"
test "$(cat "$aws_calls")" = "s3 sync s3://bucket/resourcepacks $INPUT_RESOURCEPACKS_DIR"
test -f "$INPUT_RESOURCEPACKS_DIR/example.zip"
test ! -d "$INPUT_RESOURCEPACKS_DIR/resourcepacks"

INPUT_RESOURCEPACKS_DIR="$tmp/unset-resourcepacks"
unset RESOURCEPACKS_S3_BUCKET
unset RESOURCEPACKS_S3_PREFIX
reset_calls
output="$(install_resourcepacks 2>&1)"
printf '%s\n' "$output" | grep -q 'RESOURCEPACKS_S3_BUCKET or RESOURCEPACKS_S3_PREFIX not set, skipping resourcepacks'
assert_no_s3_calls
test ! -e "$INPUT_RESOURCEPACKS_DIR"

(
  # shellcheck disable=SC2031  # Parent temp directory is intentionally read from this subshell.
  DATA_DIR="$tmp/properties-url"
  APPLY_SERVER_PROPERTIES_DIFF=true
  RESOURCE_PACK='https://cdn.example.test/resourcepacks/example.zip'
  REQUIRE_RESOURCE_PACK=true
  export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF RESOURCE_PACK REQUIRE_RESOURCE_PACK

  source ./scripts/lib/logging.sh
  source ./scripts/lib/runtime.sh
  source ./scripts/lib/server_properties.sh

  mkdir -p "$DATA_DIR"
  printf '%s\n' \
    'resource-pack=' \
    'require-resource-pack=false' \
    'custom-key=keep' > "$DATA_DIR/server.properties"

  apply_server_properties_diff >/dev/null 2>&1
  grep -Fx 'resource-pack=https://cdn.example.test/resourcepacks/example.zip' "$DATA_DIR/server.properties" >/dev/null
  grep -Fx 'require-resource-pack=true' "$DATA_DIR/server.properties" >/dev/null
  grep -Fx 'custom-key=keep' "$DATA_DIR/server.properties" >/dev/null
)

(
  # shellcheck disable=SC2031  # Parent temp directory is intentionally read from this subshell.
  DATA_DIR="$tmp/properties-explicit-precedence"
  APPLY_SERVER_PROPERTIES_DIFF=true
  RESOURCE_PACK='https://cdn.example.test/manual.zip'
  RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true
  RESOURCEPACKS_PUBLIC_BASE_URL='https://assets.example.test'
  RESOURCEPACKS_S3_PREFIX='fabric/prison/resourcepacks'
  RESOURCEPACKS_FILE='generated.zip'
  export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF RESOURCE_PACK
  export RESOURCEPACKS_AUTO_SET_RESOURCE_PACK RESOURCEPACKS_PUBLIC_BASE_URL RESOURCEPACKS_S3_PREFIX RESOURCEPACKS_FILE

  source ./scripts/lib/logging.sh
  source ./scripts/lib/runtime.sh
  source ./scripts/lib/server_properties.sh

  mkdir -p "$DATA_DIR"
  printf '%s\n' 'resource-pack=' > "$DATA_DIR/server.properties"

  prepare_resourcepack_public_url_env
  apply_server_properties_diff >/dev/null 2>&1
  grep -Fx 'resource-pack=https://cdn.example.test/manual.zip' "$DATA_DIR/server.properties" >/dev/null
  if grep -F 'generated.zip' "$DATA_DIR/server.properties" >/dev/null; then
    echo "FAIL: generated resource-pack URL overrode explicit RESOURCE_PACK" >&2
    exit 1
  fi
)

(
  # shellcheck disable=SC2031  # Parent temp directory is intentionally read from this subshell.
  DATA_DIR="$tmp/properties-generated-url"
  APPLY_SERVER_PROPERTIES_DIFF=true
  RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true
  RESOURCEPACKS_PUBLIC_BASE_URL='https://assets.example.test'
  RESOURCEPACKS_S3_PREFIX='fabric/prison/resourcepacks'
  RESOURCEPACKS_FILE='pack.zip'
  export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF
  export RESOURCEPACKS_AUTO_SET_RESOURCE_PACK RESOURCEPACKS_PUBLIC_BASE_URL RESOURCEPACKS_S3_PREFIX RESOURCEPACKS_FILE
  unset RESOURCE_PACK

  source ./scripts/lib/logging.sh
  source ./scripts/lib/runtime.sh
  source ./scripts/lib/server_properties.sh

  mkdir -p "$DATA_DIR"
  printf '%s\n' 'resource-pack=' > "$DATA_DIR/server.properties"

  prepare_resourcepack_public_url_env
  apply_server_properties_diff >/dev/null 2>&1
  grep -Fx 'resource-pack=https://assets.example.test/fabric/prison/resourcepacks/pack.zip' "$DATA_DIR/server.properties" >/dev/null
)

(
  # shellcheck disable=SC2031  # Parent temp directory is intentionally read from this subshell.
  DATA_DIR="$tmp/properties-generated-url-slashes"
  APPLY_SERVER_PROPERTIES_DIFF=true
  RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true
  RESOURCEPACKS_PUBLIC_BASE_URL='https://assets.example.test/'
  RESOURCEPACKS_S3_PREFIX='/fabric/prison/resourcepacks/'
  RESOURCEPACKS_FILE='/pack.zip'
  export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF
  export RESOURCEPACKS_AUTO_SET_RESOURCE_PACK RESOURCEPACKS_PUBLIC_BASE_URL RESOURCEPACKS_S3_PREFIX RESOURCEPACKS_FILE
  unset RESOURCE_PACK

  source ./scripts/lib/logging.sh
  source ./scripts/lib/runtime.sh
  source ./scripts/lib/server_properties.sh

  mkdir -p "$DATA_DIR"
  printf '%s\n' 'resource-pack=' > "$DATA_DIR/server.properties"

  prepare_resourcepack_public_url_env
  apply_server_properties_diff >/dev/null 2>&1
  grep -Fx 'resource-pack=https://assets.example.test/fabric/prison/resourcepacks/pack.zip' "$DATA_DIR/server.properties" >/dev/null
  if grep -F 'assets.example.test//fabric' "$DATA_DIR/server.properties" >/dev/null; then
    echo "FAIL: generated resource-pack URL contains malformed boundary slashes" >&2
    exit 1
  fi
  if grep -F 'resourcepacks/resourcepacks' "$DATA_DIR/server.properties" >/dev/null; then
    echo "FAIL: generated resource-pack URL duplicated resourcepacks path components" >&2
    exit 1
  fi
)

(
  # shellcheck disable=SC2031  # Parent temp directory is intentionally read from this subshell.
  DATA_DIR="$tmp/properties-auto-disabled"
  APPLY_SERVER_PROPERTIES_DIFF=true
  RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=false
  RESOURCEPACKS_PUBLIC_BASE_URL='https://assets.example.test'
  RESOURCEPACKS_S3_PREFIX='fabric/prison/resourcepacks'
  RESOURCEPACKS_FILE='pack.zip'
  export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF
  export RESOURCEPACKS_AUTO_SET_RESOURCE_PACK RESOURCEPACKS_PUBLIC_BASE_URL RESOURCEPACKS_S3_PREFIX RESOURCEPACKS_FILE
  unset RESOURCE_PACK

  source ./scripts/lib/logging.sh
  source ./scripts/lib/runtime.sh
  source ./scripts/lib/server_properties.sh

  mkdir -p "$DATA_DIR"
  printf '%s\n' 'custom-key=keep' > "$DATA_DIR/server.properties"

  prepare_resourcepack_public_url_env
  apply_server_properties_diff >/dev/null 2>&1
  grep -Fx 'custom-key=keep' "$DATA_DIR/server.properties" >/dev/null
  if grep -F 'resource-pack=' "$DATA_DIR/server.properties" >/dev/null; then
    echo "FAIL: RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=false wrote resource-pack" >&2
    exit 1
  fi
)

(
  # shellcheck disable=SC2031  # Parent temp directory is intentionally read from this subshell.
  DATA_DIR="$tmp/properties-auto-missing-base"
  APPLY_SERVER_PROPERTIES_DIFF=true
  RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true
  RESOURCEPACKS_S3_PREFIX='fabric/prison/resourcepacks'
  RESOURCEPACKS_FILE='pack.zip'
  export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF RESOURCEPACKS_AUTO_SET_RESOURCE_PACK RESOURCEPACKS_S3_PREFIX RESOURCEPACKS_FILE
  unset RESOURCE_PACK
  unset RESOURCEPACKS_PUBLIC_BASE_URL

  source ./scripts/lib/logging.sh
  source ./scripts/lib/runtime.sh
  source ./scripts/lib/server_properties.sh

  mkdir -p "$DATA_DIR"
  printf '%s\n' 'resource-pack=' > "$DATA_DIR/server.properties"

  set +e
  output="$(prepare_resourcepack_public_url_env 2>&1)"
  status=$?
  set -e

  test "$status" -eq 1
  printf '%s\n' "$output" | grep -q 'RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true but RESOURCEPACKS_PUBLIC_BASE_URL is empty'
)

(
  # shellcheck disable=SC2031  # Parent temp directory is intentionally read from this subshell.
  DATA_DIR="$tmp/properties-auto-missing-file"
  APPLY_SERVER_PROPERTIES_DIFF=true
  RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true
  RESOURCEPACKS_PUBLIC_BASE_URL='https://assets.example.test'
  RESOURCEPACKS_S3_PREFIX='fabric/prison/resourcepacks'
  export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF RESOURCEPACKS_AUTO_SET_RESOURCE_PACK RESOURCEPACKS_PUBLIC_BASE_URL RESOURCEPACKS_S3_PREFIX
  unset RESOURCE_PACK
  unset RESOURCEPACKS_FILE

  source ./scripts/lib/logging.sh
  source ./scripts/lib/runtime.sh
  source ./scripts/lib/server_properties.sh

  mkdir -p "$DATA_DIR"
  printf '%s\n' 'resource-pack=' > "$DATA_DIR/server.properties"

  set +e
  output="$(prepare_resourcepack_public_url_env 2>&1)"
  status=$?
  set -e

  test "$status" -eq 1
  printf '%s\n' "$output" | grep -q 'RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true but RESOURCEPACKS_FILE is empty'
)

(
  # shellcheck disable=SC2031  # Parent temp directory is intentionally read from this subshell.
  DATA_DIR="$tmp/properties-base-includes-prefix"
  APPLY_SERVER_PROPERTIES_DIFF=true
  RESOURCEPACKS_AUTO_SET_RESOURCE_PACK=true
  RESOURCEPACKS_PUBLIC_BASE_URL='https://assets.example.test/fabric/prison/resourcepacks'
  RESOURCEPACKS_S3_PREFIX='fabric/prison/resourcepacks'
  RESOURCEPACKS_FILE='pack.zip'
  export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF
  export RESOURCEPACKS_AUTO_SET_RESOURCE_PACK RESOURCEPACKS_PUBLIC_BASE_URL RESOURCEPACKS_S3_PREFIX RESOURCEPACKS_FILE
  unset RESOURCE_PACK

  source ./scripts/lib/logging.sh
  source ./scripts/lib/runtime.sh
  source ./scripts/lib/server_properties.sh

  mkdir -p "$DATA_DIR"
  printf '%s\n' 'resource-pack=' > "$DATA_DIR/server.properties"

  set +e
  output="$(prepare_resourcepack_public_url_env 2>&1)"
  status=$?
  set -e

  test "$status" -eq 1
  printf '%s\n' "$output" | grep -q 'RESOURCEPACKS_PUBLIC_BASE_URL must be the public bucket-root URL'
)

(
  # shellcheck disable=SC2031  # Parent temp directory is intentionally read from this subshell.
  DATA_DIR="$tmp/properties-s3-url"
  APPLY_SERVER_PROPERTIES_DIFF=true
  RESOURCE_PACK='s3://bucket/resourcepacks/example.zip'
  export DATA_DIR APPLY_SERVER_PROPERTIES_DIFF RESOURCE_PACK

  source ./scripts/lib/logging.sh
  source ./scripts/lib/runtime.sh
  source ./scripts/lib/server_properties.sh

  mkdir -p "$DATA_DIR"
  printf '%s\n' 'resource-pack=https://old.example.test/pack.zip' > "$DATA_DIR/server.properties"

  set +e
  output="$(apply_server_properties_diff 2>&1)"
  status=$?
  set -e

  test "$status" -eq 1
  printf '%s\n' "$output" | grep -q 'Invalid resource-pack URL'
  grep -Fx 'resource-pack=https://old.example.test/pack.zip' "$DATA_DIR/server.properties" >/dev/null
  if grep -F 'resource-pack=s3/' "$DATA_DIR/server.properties" >/dev/null; then
    echo "FAIL: internal S3 path was written to resource-pack" >&2
    exit 1
  fi
)

TYPE=fabric
PLUGINS_ENABLED=true
unset PLUGINS_S3_BUCKET
output="$({ install_plugins; activate_plugins; } 2>&1)"
test "$(printf '%s\n' "$output" | grep -c 'Install plugins (Paper | Purpur | Mohist | Taiyitist | Youer | Velocity only)')" -eq 1
