#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${ROOT_DIR}"

grep -F "api.papermc.io/v2/projects/paper" scripts/lib/server_install.sh >/dev/null && {
  echo "FAIL: Paper installer still references PaperMC v2 API" >&2
  exit 1
}
grep -F "fill.papermc.io/v3/projects/paper" scripts/lib/server_install.sh >/dev/null
grep -F "forge-\\K[0-9.]" scripts/lib/server_install.sh >/dev/null && {
  echo "FAIL: Forge installer still uses HTML artifact regex parsing" >&2
  exit 1
}
grep -F "promotions_slim.json" scripts/lib/server_install.sh >/dev/null

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/data" "$tmp/fixtures"

cat > "$tmp/fixtures/paper-builds.json" <<'EOF'
[
  {
    "id": 101,
    "time": "2026-01-01T00:00:00Z",
    "channel": "STABLE",
    "downloads": {
      "server:default": {
        "url": "https://downloads.example.test/paper-101.jar"
      }
    }
  },
  {
    "id": 102,
    "time": "2026-01-02T00:00:00Z",
    "channel": "STABLE",
    "downloads": {
      "server:default": {
        "url": "https://downloads.example.test/paper-102.jar"
      }
    }
  },
  {
    "id": 201,
    "time": "2026-01-03T00:00:00Z",
    "channel": "BETA",
    "downloads": {
      "server:default": {
        "url": "https://downloads.example.test/paper-201.jar"
      }
    }
  }
]
EOF

cat > "$tmp/fixtures/forge-promotions.json" <<'EOF'
{
  "promos": {
    "26.1.2-latest": "64.0.11",
    "1.20.1-latest": "47.4.20",
    "1.20.1-recommended": "47.4.19"
  }
}
EOF

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
    -H)
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

printf '%s\n' "$url" >> "${CURL_LOG:?}"

case "$url" in
  https://fill.papermc.io/v3/projects/paper/versions/1.21.8/builds)
    cat "${FIXTURE_DIR:?}/paper-builds.json"
    ;;
  https://downloads.example.test/paper-101.jar)
    [[ -n "$out" ]] || exit 43
    printf '%s\n' "fake paper 101 jar" > "$out"
    ;;
  https://downloads.example.test/paper-102.jar)
    [[ -n "$out" ]] || exit 44
    printf '%s\n' "fake paper 102 jar" > "$out"
    ;;
  https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json)
    cat "${FIXTURE_DIR:?}/forge-promotions.json"
    ;;
  https://maven.minecraftforge.net/net/minecraftforge/forge/26.1.2-64.0.11/forge-26.1.2-64.0.11-installer.jar)
    [[ -n "$out" ]] || exit 45
    printf '%s\n' "fake forge installer" > "$out"
    ;;
  *)
    printf 'unexpected curl URL: %s\n' "$url" >&2
    exit 46
    ;;
esac
EOF

cat > "$tmp/bin/java" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

data_dir=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --installServer)
      data_dir="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

test -n "$data_dir"
printf '%s\n' '#!/usr/bin/env bash' > "$data_dir/run.sh"
chmod +x "$data_dir/run.sh"
EOF

chmod +x "$tmp/bin/curl" "$tmp/bin/java"
PATH="$tmp/bin:$PATH"
FIXTURE_DIR="$tmp/fixtures"
CURL_LOG="$tmp/curl.log"
export FIXTURE_DIR CURL_LOG

source ./scripts/lib/logging.sh
source ./scripts/lib/filesystem.sh
source ./scripts/lib/runtime.sh
source ./scripts/lib/server_install.sh

DATA_DIR="$tmp/data"

VERSION="1.21.8"
install_paper_server_artifact
jq -e '.artifact == "server.jar" and .type == "paper" and .version == "1.21.8" and .build == "102"' \
  "$DATA_DIR/.server-install.json" >/dev/null
grep -F "https://downloads.example.test/paper-102.jar" "$CURL_LOG" >/dev/null

safe_rm_f "$DATA_DIR/server.jar"
safe_rm_f "$DATA_DIR/.server-install.json"
: > "$CURL_LOG"

PAPER_BUILD=101
install_paper_server_artifact
unset PAPER_BUILD
jq -e '.artifact == "server.jar" and .type == "paper" and .version == "1.21.8" and .build == "101"' \
  "$DATA_DIR/.server-install.json" >/dev/null
grep -F "https://downloads.example.test/paper-101.jar" "$CURL_LOG" >/dev/null

safe_rm_f "$DATA_DIR/server.jar"
safe_rm_f "$DATA_DIR/.server-install.json"
: > "$CURL_LOG"

VERSION="26.1.2"
install_forge_server_artifact
jq -e '.artifact == "run.sh" and .type == "forge" and .version == "26.1.2" and .build == "64.0.11"' \
  "$DATA_DIR/.server-install.json" >/dev/null
grep -F "https://maven.minecraftforge.net/net/minecraftforge/forge/26.1.2-64.0.11/forge-26.1.2-64.0.11-installer.jar" \
  "$CURL_LOG" >/dev/null
