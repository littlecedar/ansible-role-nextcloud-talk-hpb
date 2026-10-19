#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Travis Wichert
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Resolve the latest Janus release and update the image pins.
#
# Updates, when a newer release exists:
#   - `build/janus/Dockerfile`: `ARG JANUS_VERSION` and `ARG JANUS_COMMIT`
#   - `defaults/main.yml`: the Janus image tag and the self-build role release tag
#
# Emits `previous`, `version`, `commit` and `changed` as key=values, to
# $GITHUB_OUTPUT when set and to stdout otherwise.
set -euo pipefail

janus_repo="${JANUS_REPO:-meetecho/janus-gateway}"
dockerfile="${DOCKERFILE:-build/janus/Dockerfile}"
defaults_file="${DEFAULTS_FILE:-defaults/main.yml}"
repo_url="https://github.com/${janus_repo}.git"

emit() {
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
    else
        printf '%s=%s\n' "$1" "$2"
    fi
}

for file in "$dockerfile" "$defaults_file"; do
    if [ ! -f "$file" ]; then
        echo "update-janus: $file not found" >&2
        exit 1
    fi
done

current=$(sed -n 's/^ARG JANUS_VERSION=\(.*\)$/\1/p' "$dockerfile" | head -n 1)
if [ -z "$current" ]; then
    echo "update-janus: cannot read 'ARG JANUS_VERSION=' from $dockerfile" >&2
    exit 1
fi

latest=$(
    git ls-remote --tags --refs "$repo_url" \
        | sed 's#.*refs/tags/##' \
        | sed -n 's/^v\([0-9]\+\.[0-9]\+\.[0-9]\+\)$/\1/p' \
        | sort -V \
        | tail -n 1
)
if [ -z "$latest" ]; then
    echo "update-janus: no vX.Y.Z tag found in $repo_url" >&2
    exit 1
fi

# Annotated tags point at a tag object; `^{}` dereferences to the commit.
commit=$(git ls-remote "$repo_url" "refs/tags/v${latest}^{}" | awk '{print $1}' | head -n 1)
if [ -z "$commit" ]; then
    commit=$(git ls-remote "$repo_url" "refs/tags/v${latest}" | awk '{print $1}' | head -n 1)
fi
if [ -z "$commit" ]; then
    echo "update-janus: cannot resolve the commit of v${latest}" >&2
    exit 1
fi

emit previous "$current"
emit version "$latest"
emit commit "$commit"

if [ "$current" = "$latest" ]; then
    emit changed false
    echo "update-janus: already at Janus $current" >&2
    exit 0
fi

emit changed true
sed -i "s/^ARG JANUS_VERSION=.*/ARG JANUS_VERSION=${latest}/" "$dockerfile"
sed -i "s/^ARG JANUS_COMMIT=.*/ARG JANUS_COMMIT=${commit}/" "$dockerfile"
sed -i "s/^nextcloud_talk_hpb_janus_container_image_tag: .*/nextcloud_talk_hpb_janus_container_image_tag: \"${latest}\"/" "$defaults_file"
sed -i "s/^nextcloud_talk_hpb_janus_container_image_self_build_repo_version: .*/nextcloud_talk_hpb_janus_container_image_self_build_repo_version: \"v${latest}-0\"/" "$defaults_file"

echo "update-janus: $current -> $latest ($commit)" >&2
