#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/data"

cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

out=""
url=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

case "$url" in
  https://meta.fabricmc.net/v2/versions/loader/*)
    printf '%s\n' "unexpected loader metadata request" >&2
    exit 42
    ;;
  https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.0.3/fabric-installer-1.0.3.jar)
    [[ -n "$out" ]] || exit 43
    printf '%s\n' "fake installer" > "$out"
    ;;
  *)
    printf 'unexpected curl URL: %s\n' "$url" >&2
    exit 44
    ;;
esac
EOF

cat > "$tmp/bin/java" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

loader=""
data_dir=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -loader)
      loader="$2"
      shift 2
      ;;
    -dir)
      data_dir="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

test "$loader" = "0.16.14"
test -n "$data_dir"
touch "$data_dir/fabric-server-launch.jar"
EOF

chmod +x "$tmp/bin/curl" "$tmp/bin/java"
PATH="$tmp/bin:$PATH"

source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh
source ./scripts/lib/runtime.sh
source ./scripts/lib/server_install.sh

DATA_DIR="$tmp/data"
VERSION="1.21.8"
FABRIC_LOADER_VERSION="0.16.14"
FABRIC_INSTALLER_VERSION="1.0.3"

install_fabric_server_artifact

jq -e '.artifact == "fabric-server-launch.jar" and .type == "fabric" and .version == "1.21.8" and .build == "0.16.14"' \
  "$DATA_DIR/.server-install.json" >/dev/null
