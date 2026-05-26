# shellcheck shell=bash

detect_runtime_env() {
  log INFO "Detecting runtime environment..."

  # ---- OS ----
  if [[ -f /etc/os-release ]]; then
    RUNTIME_OS="$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
    RUNTIME_OS_VERSION="$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
  else
    RUNTIME_OS="unknown"
    RUNTIME_OS_VERSION="unknown"
  fi

  JAVA_VERSION_RAW="$(java -version 2>&1 | head -n 1 || true)"
  JAVA_MAJOR="$(
    java -XshowSettings:properties -version 2>&1 \
      | awk -F= '/java.specification.version/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' \
      | sed 's/^1\.//'
  )"
  [[ -n "${JAVA_MAJOR}" ]] || JAVA_MAJOR="unknown"

  RUNTIME_ARCH_NORM="$(uname -m)"
  case "${RUNTIME_ARCH_NORM}" in
    amd64) RUNTIME_ARCH_NORM="x86_64" ;;
    aarch64|arm64) RUNTIME_ARCH_NORM="arm64" ;;
  esac

  if [[ -f /.dockerenv || -f /run/.containerenv || -n "${container:-}" ]]; then
    RUNTIME_CONTAINER="true"
  else
    RUNTIME_CONTAINER="false"
  fi

  if [[ -e /dev/nvidia0 || -e /dev/dxg || -d /dev/dri ]]; then
    RUNTIME_GPU="present"
  else
    RUNTIME_GPU="none"
  fi

  export RUNTIME_OS RUNTIME_OS_VERSION JAVA_VERSION_RAW JAVA_MAJOR RUNTIME_ARCH_NORM RUNTIME_CONTAINER RUNTIME_GPU
}
