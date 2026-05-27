# shellcheck shell=bash

require_yq() {
  command -v yq >/dev/null 2>&1 || die "yq is required to edit YAML configs (install yq in the image)"
}

validate_server_properties_key() {
  local key="$1"
  [[ "$key" =~ ^[A-Za-z0-9._-]+$ ]] \
    || die "Invalid server.properties key: '${key}'"
}

# Apply key=value to server.properties (replace if exists, append if not)
set_server_properties_kv() {
  local file="$1" key="$2" value="$3"
  local tmp_file

  validate_server_properties_key "$key"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp_file="$(mktemp "${file}.XXXXXX")" || die "Failed to create temporary file for '${file}'"

  if ! awk -v key="$key" -v value="$value" '
    BEGIN {
      found = 0
    }
    {
      line = $0
      if (match(line, /^[[:space:]]*[^=]+[[:space:]]*=/)) {
        candidate = substr(line, 1, RLENGTH)
        sub(/^[[:space:]]*/, "", candidate)
        sub(/[[:space:]]*=$/, "", candidate)
        if (candidate == key) {
          print key "=" value
          found = 1
          next
        }
      }
      print line
    }
    END {
      if (!found) {
        print key "=" value
      }
    }
  ' "$file" > "$tmp_file"; then
    rm -f "$tmp_file"
    die "Failed to update server.properties file '${file}'"
  fi

  mv "$tmp_file" "$file" || {
    rm -f "$tmp_file"
    die "Failed to replace server.properties file '${file}'"
  }
}

# Set value on YAML dot path (roughly detect true/false/number/string types)
yq_set_yaml() {
  local file="$1" path="$2" value="$3"

  require_yq
  mkdir -p "$(dirname "$file")"
  touch "$file"

  # Keep type-like values as-is, treat others as strings
  if [[ "$value" =~ ^(true|false|null)$ ]] || [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    yq -i ".${path} = ${value}" "$file"
  else
    # Escape double quotes
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    yq -i ".${path} = \"${value}\"" "$file"
  fi
}

# Apply one "file:path=value" item
apply_paper_override_item() {
  local base_dir="$1" item="$2"
  item="$(trim_ws "$item")"
  [[ -n "$item" ]] || return 0

  local left="${item%%=*}"
  local value="${item#*=}"

  local file="${left%%:*}"
  local path="${left#*:}"

  file="$(trim_ws "$file")"
  path="$(trim_ws "$path")"
  value="$(trim_ws "$value")"

  [[ -n "$file" && -n "$path" && "$left" == *":"* && "$item" == *"="* ]] \
    || die "Invalid PAPER_CONFIG_OVERRIDES item: '${item}' (expected file:path=value)"

  local target="${base_dir}/${file}"

  # Only server.properties is treated as properties file (path=key)
  if [[ "${file}" == "server.properties" ]]; then
    set_server_properties_kv "$target" "$path" "$value"
    return 0
  fi

  # Treat other files as YAML (can add more branches by filename if needed)
  yq_set_yaml "$target" "$path" "$value"
}

configure_paper_configs() {
  [[ "${TYPE:-}" == "paper" ]] || return 0

  local cfg_dir="${PAPER_CONFIG_DIR:-${DATA_DIR}/config}"
  mkdir -p "$cfg_dir"

  if is_true "${PAPER_VELOCITY:-false}"; then
    local secret="${PAPER_VELOCITY_SECRET:-${VELOCITY_SECRET:-}}"
    [[ -n "$secret" ]] || die "PAPER_VELOCITY=true but no PAPER_VELOCITY_SECRET or VELOCITY_SECRET"

    if command -v yq >/dev/null 2>&1; then
      # Always write these; yq_set_yaml assumes touch/creation
      yq_set_yaml "${cfg_dir}/paper-global.yml" "proxies.velocity.enabled" "true"
      yq_set_yaml "${cfg_dir}/paper-global.yml" "proxies.velocity.secret" "$secret"

      # Do the same for legacy setups (regardless of file presence)
      yq_set_yaml "${cfg_dir}/paper.yml" "settings.velocity-support.enabled" "true"
      yq_set_yaml "${cfg_dir}/paper.yml" "settings.velocity-support.secret" "$secret"

      yq_set_yaml "${cfg_dir}/spigot.yml" "settings.bungeecord" "true"
    else
      log WARN "yq not found; paper-global.yml will use minimal fallback and legacy Paper files are skipped"
    fi
  fi

  if [[ -n "${PAPER_CONFIG_OVERRIDES:-}" ]]; then
    require_yq
    local -a items
    IFS=',' read -ra items <<< "${PAPER_CONFIG_OVERRIDES}"
    local it
    for it in "${items[@]}"; do
      apply_paper_override_item "$cfg_dir" "$it"
    done
  fi

  log INFO "Paper configs applied under: ${cfg_dir}"
}

# --- YAML helper: escape a string for double-quoted YAML scalars ---
yaml_escape_dq() {
  local s="$1"
  s="${s//\\/\\\\}"   # \  -> \\
  s="${s//\"/\\\"}"   # "  -> \"
  printf '%s' "$s"
}

# --- Paper: apply config/paper-global.yml from environment variables ---
# Expected ENV:
#   PAPER_VELOCITY=true
#   PAPER_VELOCITY_SECRET=<must match Velocity forwarding.secret>
#
# Fallback:
#   If PAPER_VELOCITY_SECRET is empty, VELOCITY_SECRET is used.
#
# Optional:
#   PAPER_VELOCITY_ONLINE_MODE=true|false (usually true)
#   PAPER_VELOCITY_ENABLED=true|false (usually true)
apply_paper_global_from_env() {
  [[ "${TYPE:-}" == "paper" ]] || return 0
  is_true "${PAPER_VELOCITY:-false}" || return 0

  local cfg_dir="${PAPER_CONFIG_DIR:-${DATA_DIR}/config}"
  local file="${cfg_dir}/paper-global.yml"

  local enabled="${PAPER_VELOCITY_ENABLED:-true}"
  local online_mode="${PAPER_VELOCITY_ONLINE_MODE:-true}"
  local secret="${PAPER_VELOCITY_SECRET:-${VELOCITY_SECRET:-}}"

  [[ -n "$secret" ]] || die "PAPER_VELOCITY=true but no PAPER_VELOCITY_SECRET (or VELOCITY_SECRET)"

  mkdir -p "$cfg_dir"
  touch "$file"

  # If yq is available, update only the required keys without destroying other settings.
  if command -v yq >/dev/null 2>&1; then
    yq -i ".proxies.velocity.enabled = ${enabled}" "$file"
    yq -i ".proxies.velocity.online-mode = ${online_mode}" "$file"
    yq -i ".proxies.velocity.secret = \"$(yaml_escape_dq "$secret")\"" "$file"
    log INFO "paper-global.yml updated via yq: $file"
    return 0
  fi

  # If yq is not available, generate a minimal file via tee (this overwrites the file).
  log WARN "yq not found; generating minimal paper-global.yml via tee (overwrites file): $file"
  cat <<EOF | tee "$file" >/dev/null
proxies:
  velocity:
    enabled: ${enabled}
    online-mode: ${online_mode}
    secret: "$(yaml_escape_dq "$secret")"
EOF
  log INFO "paper-global.yml generated via tee: $file"
}
