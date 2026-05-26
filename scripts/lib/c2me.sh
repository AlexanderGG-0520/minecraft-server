# shellcheck shell=bash

should_enable_c2me() {
  # ---- Explicit user consent ----
  [[ "${ENABLE_C2ME}" == "true" ]] || return 1
  [[ "${ENABLE_C2ME_HARDWARE_ACCELERATION}" == "true" ]] || return 1
  [[ "${I_KNOW_C2ME_IS_EXPERIMENTAL}" == "true" ]] || return 1

  # ---- Java guard ----
  [[ "${JAVA_MAJOR}" == "25" ]] || return 1

  # ---- Runtime guard ----
  [[ "${RUNTIME_ARCH_NORM}" == "x86_64" ]] || return 1
  [[ "${RUNTIME_CONTAINER}" == "true" ]] || return 1
  [[ "${RUNTIME_GPU}" != "none" ]] || return 1

  # ---- Device guard ----
  [[ -d /dev/dri || -e /dev/nvidia0 || -e /dev/dxg ]] || return 1

  return 0
}

detect_optimize_mod() {
  local name="$1"
  ls "${DATA_DIR}/mods"/"${name}"*.jar >/dev/null 2>&1
}

has_c2me_mod() {
  detect_optimize_mod "c2me"
}

install_c2me_jvm_args() {
  if ! has_c2me_mod; then
    log INFO "C2ME mod not found in mods/, skipping"
    return 0
  fi

  if ! detect_gpu; then
    log INFO "CPU-only environment detected, skipping ALL C2ME optimizations"
    return 0
  fi

  if should_enable_c2me; then
    log WARN "C2ME Hardware Acceleration ENABLED (EXPERIMENTAL)"
    log WARN "This may cause instability or data corruption"

    {
      echo ""
      echo "# --- C2ME Hardware Acceleration (EXPERIMENTAL) ---"
      echo "-Dc2me.experimental.hardwareAcceleration=true"
      echo "-Dc2me.experimental.opencl=true"
      echo "-Dc2me.experimental.unsafe=true"
    } >> "${JVM_ARGS_FILE}"
  else
    log INFO "C2ME mod present, but guard conditions not met"
  fi
}

detect_gpu() {
  log INFO "Detecting OpenCL GPU availability..."

  # ------------------------------------------------------------
  # 1. GPU device (Docker / WSL compatible)
  # ------------------------------------------------------------
  if [ ! -e /dev/nvidia0 ] && [ ! -e /dev/dxg ]; then
    log INFO "No NVIDIA GPU device found (/dev/nvidia* or /dev/dxg)"
    return 1
  fi
  log INFO "GPU device node found"

  # ------------------------------------------------------------
  # 2. OpenCL loader (path-based, not ldconfig)
  # ------------------------------------------------------------
  if ! find /usr/lib /usr/local/lib -path '*libOpenCL.so*' -print -quit 2>/dev/null | grep -q .; then
    log WARN "OpenCL loader (libOpenCL.so) not found"
    return 1
  fi
  log INFO "OpenCL loader present"

  # ------------------------------------------------------------
  # 3. clinfo is diagnostic only; containerized OpenCL can work
  #    even when clinfo is missing or unreliable.
  # ------------------------------------------------------------
  if ! command -v clinfo >/dev/null 2>&1; then
    log WARN "clinfo not available; continuing with device + loader detection"
    return 0
  fi

  if ! clinfo --raw 2>/dev/null | grep -qi "NVIDIA"; then
    log WARN "clinfo did not report NVIDIA; continuing because clinfo is not authoritative"
    return 0
  fi

  log INFO "OpenCL GPU detected"
  return 0
}

configure_c2me_opencl() {
  if ! has_c2me_mod; then
    return
  fi

  if [[ "${C2ME_OPENCL_FORCE:-auto}" == "true" ]]; then
    log WARN "C2ME OpenCL FORCE ENABLED"
    export C2ME_OPENCL_ENABLED=true
    return
  fi

  if detect_gpu; then
    export C2ME_OPENCL_ENABLED=true
    log INFO "C2ME OpenCL enabled (GPU mode)"
  else
    export C2ME_OPENCL_ENABLED=false
    log INFO "C2ME OpenCL disabled (CPU-safe mode)"
  fi
}
