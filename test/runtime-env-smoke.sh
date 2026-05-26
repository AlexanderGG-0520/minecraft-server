#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"

cat > "$tmp/bin/java" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

for arg in "$@"; do
  if [[ "$arg" == "-XshowSettings:properties" ]]; then
    printf '%s\n' "    java.specification.version = 25" >&2
    exit 0
  fi
done

printf '%s\n' 'openjdk version "25"' >&2
EOF

cat > "$tmp/bin/uname" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" == "-m" ]]; then
  printf '%s\n' "aarch64"
  exit 0
fi

exit 1
EOF

cat > "$tmp/bin/grep" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" == "^ID=" && "${2:-}" == "/etc/os-release" ]]; then
  printf '%s\n' "ID=runtime-env-smoke"
  exit 0
fi

if [[ "${1:-}" == "^VERSION_ID=" && "${2:-}" == "/etc/os-release" ]]; then
  printf '%s\n' "VERSION_ID=1"
  exit 0
fi

exec /usr/bin/grep "$@"
EOF

chmod +x "$tmp/bin/java" "$tmp/bin/uname" "$tmp/bin/grep"

PATH="$tmp/bin:$PATH"

source ./scripts/lib/logging.sh
source ./scripts/lib/runtime_env.sh

detect_runtime_env >/dev/null

test "$JAVA_VERSION_RAW" = 'openjdk version "25"'
test "$JAVA_MAJOR" = "25"
test "$RUNTIME_OS" = "runtime-env-smoke"
test "$RUNTIME_OS_VERSION" = "1"
test "$RUNTIME_ARCH_NORM" = "arm64"
case "$RUNTIME_CONTAINER" in
  true|false) ;;
  *) exit 1 ;;
esac
case "$RUNTIME_GPU" in
  present|none) ;;
  *) exit 1 ;;
esac
