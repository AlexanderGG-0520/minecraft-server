# shellcheck shell=bash

install_jvm_args() {
  log INFO "Generating JVM args"

  # skip if already exists
  if [[ -f "${JVM_ARGS_FILE}" ]]; then
    log INFO "jvm.args already exists, skipping generation"
    return
  fi

  : "${JVM_XMS:=512M}"
  : "${JVM_XMX:=512M}"
  : "${JVM_GC:=G1}"
  : "${JVM_EXTRA_ARGS:=}"

  {
    echo "-Xms${JVM_XMS}"
    echo "-Xmx${JVM_XMX}"

    case "${JVM_GC}" in
      G1)
        echo "-XX:+UseG1GC"
        ;;
      ZGC)
        echo "-XX:+UseZGC"
        ;;
      *)
        die "Invalid JVM_GC: ${JVM_GC}"
        ;;
    esac

    if [[ "${JVM_USE_CONTAINER_SUPPORT:-true}" == "true" ]]; then
      echo "-XX:+UseContainerSupport"
    fi

    if [[ -n "${JVM_EXTRA_ARGS}" ]]; then
      echo "${JVM_EXTRA_ARGS}"
    fi
  } > "${JVM_ARGS_FILE}"

  log INFO "jvm.args generated"
}
