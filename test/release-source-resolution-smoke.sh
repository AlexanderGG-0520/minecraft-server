#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/scripts/release/resolve-source.sh"

tmp_root="$(mktemp -d)"
trap 'rm -r -- "${tmp_root}"' EXIT

remote="${tmp_root}/remote.git"
work="${tmp_root}/work"
resolver="${tmp_root}/resolver"
git init --bare --quiet "${remote}"
git init --quiet -b main "${work}"
git -C "${work}" config user.email smoke@example.invalid
git -C "${work}" config user.name smoke
printf 'old\n' > "${work}/state"
git -C "${work}" add state
git -C "${work}" commit --quiet -m old
old_sha="$(git -C "${work}" rev-parse HEAD)"
git -C "${work}" tag v1.0.0
printf 'new\n' > "${work}/state"
git -C "${work}" commit --quiet -am new
new_sha="$(git -C "${work}" rev-parse HEAD)"
git -C "${work}" tag -a v1.1.0 -m annotated
git -C "${work}" remote add origin "${remote}"
git -C "${work}" push --quiet origin main --tags
git clone --quiet "${remote}" "${resolver}"

[[ "$(resolve_release_tag_commit "${resolver}" v1.0.0)" == "${old_sha}" ]]
[[ "$(resolve_release_tag_commit "${resolver}" v1.1.0)" == "${new_sha}" ]]

for invalid_tag in '' main missing -v1.0.0 'v1.0.0^{commit}' v1.0 1.0.0; do
    if resolve_release_tag_commit "${resolver}" "${invalid_tag}" >/dev/null 2>&1; then
        printf 'invalid release tag unexpectedly resolved: %s\n' "${invalid_tag}" >&2
        exit 1
    fi
done

printf 'release source resolution smoke test passed\n'
