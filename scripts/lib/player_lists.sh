# shellcheck shell=bash

player_list_uuid_cache_file() {
  printf '%s\n' "${DATA_DIR}/uuid_cache.json"
}

# create UUID cache file if not exists, and fail fast if it is not a JSON object
init_uuid_cache() {
  local uuid_cache_file
  uuid_cache_file="$(player_list_uuid_cache_file)"

  if [[ ! -f "$uuid_cache_file" ]]; then
    echo "{}" > "$uuid_cache_file"
    return 0
  fi

  if ! jq -e 'type == "object"' "$uuid_cache_file" >/dev/null 2>&1; then
    die "Invalid UUID cache at ${uuid_cache_file}; expected a JSON object. Fix or remove the file to regenerate it."
  fi
}

# get UUID for a given player name
uuid_for_player() {
  local name="$1"
  local cached
  local tmp
  local uuid
  local uuid_cache_file

  init_uuid_cache
  uuid_cache_file="$(player_list_uuid_cache_file)"

  cached=$(jq -r --arg n "$name" '.[$n] // empty' "$uuid_cache_file")
  if [[ -n "$cached" ]]; then
    [[ "$cached" =~ ^[0-9a-fA-F]{32}$ ]] || die "Invalid cached UUID for player '${name}'"
    echo "$cached"
    return 0
  fi

  uuid=$(curl -fsSL \
    "https://api.mojang.com/users/profiles/minecraft/${name}" \
    | jq -r '.id // empty') || return 1

  [[ -z "$uuid" ]] && return 1
  [[ "$uuid" =~ ^[0-9a-fA-F]{32}$ ]] || die "Invalid UUID returned for player '${name}'"

  tmp="$(mktemp "${uuid_cache_file}.tmp.XXXXXX")" || return 1
  if ! jq --arg n "$name" --arg u "$uuid" \
    '. + {($n): $u}' \
    "$uuid_cache_file" > "$tmp"; then
    safe_rm_f "$tmp"
    return 1
  fi
  if ! safe_mv_f "$tmp" "$uuid_cache_file"; then
    safe_rm_f "$tmp"
    return 1
  fi
  set_readable_file_permissions "$uuid_cache_file"

  echo "$uuid"
}

# transform CSV string into newline-separated list
# NOTE: this is meant to feed `while IFS= read -r ...` iteration. The main
#       hazard being avoided is `for name in $(parse_csv ...)`, where command
#       substitution plus `for ... in` triggers word splitting and globbing and
#       corrupts values containing spaces or glob characters. That issue is
#       independent of `set -u`. Prefer:
#         while IFS= read -r name; do ...; done < <(parse_csv "${CSV}")
#       This is a simple comma-separated env-var parser: it trims leading and
#       trailing whitespace and drops empty items. Embedded commas are not
#       supported.
parse_csv() {
  if [[ -z "${1:-}" ]]; then
    return 0
  fi
  printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d'
}

# transform UUID into hyphenated form
uuid_with_hyphen() {
  local u="$1"
  # format: 8-4-4-4-12
  echo "${u:0:8}-${u:8:4}-${u:12:4}-${u:16:4}-${u:20:12}"
}

# function to generate ops.json
install_ops() {
  local FILE="${DATA_DIR}/ops.json"
  local tmp
  local uuid

  # now ops is empty
  [[ -z "${OPS_USERS:-}" ]] && return

  log INFO "Generating ops.json"
  init_uuid_cache
  tmp="$(mktemp "${FILE}.tmp.XXXXXX")"

  if ! {
    while IFS= read -r name; do
      uuid=$(uuid_for_player "$name") || continue

      jq -nc \
        --arg uuid "$(uuid_with_hyphen "$uuid")" \
        --arg name "$name" \
        --argjson level 4 \
        --argjson bypassesPlayerLimit false \
        '{uuid:$uuid,name:$name,level:$level,bypassesPlayerLimit:$bypassesPlayerLimit}'
    done < <(parse_csv "${OPS_USERS}")
  } | jq -s '.' > "$tmp"; then
    safe_rm_f "$tmp"
    return 1
  fi

  if ! safe_mv_f "$tmp" "$FILE"; then
    safe_rm_f "$tmp"
    return 1
  fi
  set_readable_file_permissions "$FILE"
}

# function to generate whitelist.json
install_whitelist() {
  local FILE="${DATA_DIR}/whitelist.json"
  local tmp
  local uuid

  # now whitelist disabled or empty
  [[ "${ENABLE_WHITELIST:-false}" != "true" ]] && return
  [[ -z "${WHITELIST_USERS:-}" ]] && return

  log INFO "Generating whitelist.json"
  init_uuid_cache
  tmp="$(mktemp "${FILE}.tmp.XXXXXX")"

  if ! {
    while IFS= read -r name; do
      uuid=$(uuid_for_player "$name") || continue

      jq -nc \
        --arg uuid "$(uuid_with_hyphen "$uuid")" \
        --arg name "$name" \
        '{uuid:$uuid,name:$name}'
    done < <(parse_csv "${WHITELIST_USERS}")
  } | jq -s '.' > "$tmp"; then
    safe_rm_f "$tmp"
    return 1
  fi

  if ! safe_mv_f "$tmp" "$FILE"; then
    safe_rm_f "$tmp"
    return 1
  fi
  set_readable_file_permissions "$FILE"
}
