# shellcheck shell=bash

download_file_atomic() {
  local url="$1"
  local dest="$2"
  local label="$3"
  local tmp="${dest}.tmp.$$"

  rm -f -- "$tmp"
  if ! curl -fL "$url" -o "$tmp"; then
    rm -f -- "$tmp"
    die "Failed to download ${label}"
  fi

  [[ -s "$tmp" ]] || {
    rm -f -- "$tmp"
    die "Downloaded ${label} is empty"
  }

  mv -f "$tmp" "$dest"
}

download_vanilla_server_atomic() {
  local url="$1"
  local sha1="$2"
  local dest="$3"
  local tmp="${dest}.tmp.$$"

  rm -f -- "$tmp"
  if ! curl -fL "$url" -o "$tmp"; then
    rm -f -- "$tmp"
    die "Failed to download vanilla server.jar"
  fi

  [[ -s "$tmp" ]] || {
    rm -f -- "$tmp"
    die "Downloaded vanilla server.jar is empty"
  }

  echo "${sha1}  ${tmp}" | sha1sum -c - >/dev/null || {
    rm -f -- "$tmp"
    die "Downloaded vanilla server.jar checksum mismatch"
  }

  mv -f "$tmp" "$dest"
}
