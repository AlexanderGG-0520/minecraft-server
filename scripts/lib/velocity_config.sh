# shellcheck shell=bash

generate_velocity_toml() {
  [[ "${TYPE:-}" == "velocity" ]] || return 0

  local CONFIG_FILE="${DATA_DIR}/velocity.toml"

  rm -f "${CONFIG_FILE}"

  [[ -n "${VELOCITY_SERVERS:-}" ]] || die "VELOCITY_SERVERS is required"
  [[ -n "${VELOCITY_SECRET:-}"  ]] || die "VELOCITY_SECRET is required"

  log INFO "Generating velocity.toml"

  # For checking servers existence (not needed if declared externally, but safer this way)
  declare -gA VELOCITY_SERVER_KEYS 2>/dev/null || true
  VELOCITY_SERVER_KEYS=()

  {
    # -------------------------
    # Core settings
    # -------------------------
    cat <<EOF
bind = "${VELOCITY_BIND:-0.0.0.0:25577}"
motd = "${VELOCITY_MOTD:-<gold>Velocity</gold>}"
online-mode = ${VELOCITY_ONLINE_MODE:-true}

player-info-forwarding-mode = "modern"
forwarding-secret = "${VELOCITY_SECRET}"

EOF

    # -------------------------
    # Servers
    # -------------------------
    echo "[servers]"

    local raw_key val key entry
    local -a ENTRIES
    IFS=',' read -ra ENTRIES <<< "${VELOCITY_SERVERS}"

    local last_raw_key=""
    for entry in "${ENTRIES[@]}"; do
      entry="$(trim_ws "$entry")"
      [[ -n "$entry" ]] || continue

      raw_key="$(trim_ws "${entry%%=*}")"
      val="$(trim_ws "${entry#*=}")"

      [[ -n "$raw_key" && -n "$val" && "$entry" == *"="* ]] \
        || die "Invalid VELOCITY_SERVERS entry: '${entry}' (expected name=host:port)"

      key="$(normalize_toml_key "${raw_key}")"

      # Minimal escaping for Velocity TOML output (" and \\)
      val="${val//\\/\\\\}"
      val="${val//\"/\\\"}"

      echo "  ${key} = \"${val}\""
      VELOCITY_SERVER_KEYS["${key}"]=1

      last_raw_key="${raw_key}"
    done

    [[ -n "${last_raw_key}" ]] || die "VELOCITY_SERVERS parsed empty (check commas/spaces)"

    # -------------------------
    # Try (fallback)
    # -------------------------
    echo

    local try_src try_entry try_key
    local -a TRY_ENTRIES TRY_KEYS

    # If not specified, use last server as default (maintain original behavior)
    try_src="${VELOCITY_TRY:-${last_raw_key}}"

    IFS=',' read -ra TRY_ENTRIES <<< "${try_src}"
    for try_entry in "${TRY_ENTRIES[@]}"; do
      try_entry="$(trim_ws "$try_entry")"
      [[ -n "$try_entry" ]] || continue

      try_key="$(normalize_toml_key "${try_entry}")"

      [[ -n "${VELOCITY_SERVER_KEYS[${try_key}]:-}" ]] \
        || die "VELOCITY_TRY '${try_key}' is not defined in VELOCITY_SERVERS"

      TRY_KEYS+=("${try_key}")
    done

    [[ "${#TRY_KEYS[@]}" -gt 0 ]] || die "VELOCITY_TRY parsed empty (check commas/spaces)"

    # TOML array: try = [ "a", "b" ]
    printf 'try = [ '
    local i
    for i in "${!TRY_KEYS[@]}"; do
      [[ $i -gt 0 ]] && printf ', '
      printf '"%s"' "${TRY_KEYS[$i]}"
    done
    printf ' ]\n'

    # -------------------------
    # Forced hosts
    # -------------------------
    echo
    echo "[forced-hosts]"

    if [[ -n "${VELOCITY_FORCED_HOSTS:-}" ]]; then
      local -a HOSTS
      local h domain srv_raw srv
      IFS=',' read -ra HOSTS <<< "${VELOCITY_FORCED_HOSTS}"

      for h in "${HOSTS[@]}"; do
        h="$(trim_ws "$h")"
        [[ -n "$h" ]] || continue

        domain="$(trim_ws "${h%%:*}")"
        srv_raw="$(trim_ws "${h#*:}")"

        [[ -n "$domain" && -n "$srv_raw" && "$h" == *":"* ]] \
          || die "Invalid VELOCITY_FORCED_HOSTS item: '${h}' (expected domain:server)"

        srv="$(normalize_toml_key "${srv_raw}")"

        [[ -n "${VELOCITY_SERVER_KEYS[${srv}]:-}" ]] \
          || die "forced-host '${domain}' refers to unknown server '${srv}'"

        echo "  \"${domain}\" = [ \"${srv}\" ]"
      done
    fi
  } > "${CONFIG_FILE}"

  log INFO "velocity.toml generated"
}
