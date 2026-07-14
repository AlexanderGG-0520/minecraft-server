#!/usr/bin/env bash
# Resolve a supported release tag to its peeled commit without evaluating input.

set -Eeuo pipefail

release_tag_is_valid() {
    local release_tag="$1"
    [[ "${release_tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]
}

resolve_release_tag_commit() {
    local repository_dir="$1"
    local release_tag="$2"
    local commit_sha

    if ! release_tag_is_valid "${release_tag}"; then
        printf 'release tag must match vMAJOR.MINOR.PATCH (optional prerelease), got: %s\n' "${release_tag}" >&2
        return 2
    fi

    # The validated tag is used only as part of an explicit refs/tags refspec.
    if ! git -C "${repository_dir}" fetch --no-tags origin "refs/tags/${release_tag}:refs/tags/${release_tag}"; then
        printf 'release tag does not exist on origin: %s\n' "${release_tag}" >&2
        return 3
    fi

    if ! commit_sha="$(git -C "${repository_dir}" rev-parse --verify "refs/tags/${release_tag}^{commit}")"; then
        printf 'release tag does not resolve to a commit: %s\n' "${release_tag}" >&2
        return 4
    fi

    printf '%s\n' "${commit_sha}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$#" -ne 2 ]]; then
        printf 'usage: %s REPOSITORY_DIR RELEASE_TAG\n' "$0" >&2
        exit 64
    fi
    resolve_release_tag_commit "$1" "$2"
fi
