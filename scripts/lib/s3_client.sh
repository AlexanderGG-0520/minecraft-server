# shellcheck shell=bash

: "${MC_CONFIG_DIR:=/tmp/mc-config}"
export MC_CONFIG_DIR

require_s3_env() {
  local feature="$1"
  [[ -n "${S3_ENDPOINT:-}" ]] || die "S3_ENDPOINT is required for ${feature}"
  [[ -n "${S3_ACCESS_KEY:-}" ]] || die "S3_ACCESS_KEY is required for ${feature}"
  [[ -n "${S3_SECRET_KEY:-}" ]] || die "S3_SECRET_KEY is required for ${feature}"
}

configure_mc_alias() {
  local feature="$1"
  require_s3_env "$feature"
  mkdir -p "${MC_CONFIG_DIR}"
  mc alias set s3 "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}" >/dev/null \
    || die "Failed to configure MinIO client for ${feature}"
}

cleanup_s3_source_listing_tmp() {
  local tmp="${1:-}"

  [[ -z "$tmp" ]] || safe_rm_f "$tmp"
}

ensure_s3_source_nonempty_for_remove() {
  local src="$1"
  local feature="$2"
  local error_message=""
  local tmp=""

  tmp="$(mktemp "${TMPDIR:-/tmp}/s3-source.XXXXXX")" \
    || die "Failed to create temporary file for ${feature} source listing"

  if ! mc find "$src" --print "{}" > "$tmp"; then
    error_message="Failed to list ${feature} source before remove sync: ${src}"
  elif [[ ! -s "$tmp" ]]; then
    error_message="${feature} remove_extra requested but S3 source is empty: ${src}"
  fi

  cleanup_s3_source_listing_tmp "$tmp"
  [[ -z "$error_message" ]] || die "$error_message"
}
