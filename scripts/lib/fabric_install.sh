# shellcheck shell=bash

if declare -F install_fabric_server_artifact >/dev/null \
  && ! declare -F install_fabric_server_artifact_latest >/dev/null; then
  eval "$(
    declare -f install_fabric_server_artifact \
      | sed '1s/install_fabric_server_artifact/install_fabric_server_artifact_latest/'
  )"
fi

install_fabric_server_artifact() {
  if [[ -z "${FABRIC_LOADER_VERSION:-}" || "${FABRIC_LOADER_VERSION}" == "latest" ]]; then
    install_fabric_server_artifact_latest
    return
  fi

  (
    curl() {
      case "$*" in
        *"/v2/versions/loader/${VERSION}"*)
          jq -cn --arg loader "${FABRIC_LOADER_VERSION}" '[{loader:{version:$loader}}]'
          ;;
        *)
          command curl "$@"
          ;;
      esac
    }

    install_fabric_server_artifact_latest
  )
}
