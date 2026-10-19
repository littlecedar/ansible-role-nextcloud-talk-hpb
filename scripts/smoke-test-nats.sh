#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Travis Wichert
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Image behavior smoke test for the NATS HPB container.
set -euo pipefail

image="${1:-nextcloud-talk-hpb-nats:local}"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
dockerfile="${DOCKERFILE:-$repo_root/build/nats/Dockerfile}"

expected_version=$(sed -n 's/^ARG NATS_VERSION=\(.*\)$/\1/p' "$dockerfile" | head -n 1)
if [ -z "$expected_version" ]; then
    echo "could not parse NATS_VERSION from $dockerfile" >&2
    exit 1
fi

container="nats-smoke-$$"
tmp_dir=$(mktemp -d)

cleanup() {
    docker rm -f "$container" >/dev/null 2>&1 || true
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

pass() {
    echo "ok: $*"
}

echo "== image: $image (expected nats-server $expected_version)"

# --- 1. image metadata -------------------------------------------------------
[ "$(docker image inspect --format '{{.Config.User}}' "$image")" = "1000:1000" ] \
    || fail "image user is not 1000:1000"
if docker run --rm --entrypoint /bin/sh "$image" -c true >/dev/null 2>&1; then
    fail "/bin/sh is present (the runtime must be shell-free)"
fi
pass "user 1000:1000, no /bin/sh"

# --- 2. compiled version -----------------------------------------------------
version_output=$(docker run --rm --entrypoint /usr/local/bin/nats-server "$image" -v 2>&1)
printf '%s\n' "$version_output" | grep -qF "v$expected_version" \
    || fail "nats-server -v does not report v$expected_version"
pass "nats-server -v reports v$expected_version"

# --- 3. start the container --------------------------------------------------
config="$tmp_dir/nats.conf"
printf 'listen: 0.0.0.0:4222\nauthorization { token: smoke-token }\n' > "$config"
chmod 644 "$config"

docker run -d --name "$container" \
    --read-only \
    --tmpfs /tmp \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --user 1000:1000 \
    -v "$config:/etc/nats/nats.conf:ro" \
    -p 127.0.0.1::4222 \
    "$image" -c /etc/nats/nats.conf >/dev/null

port=""
for _ in $(seq 1 30); do
    port=$(docker port "$container" 4222/tcp 2>/dev/null | head -n 1 | sed 's/.*://')
    [ -n "$port" ] && break
    sleep 1
done
[ -n "$port" ] || fail "container did not publish port 4222"

connected=""
for _ in $(seq 1 30); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
        connected=1
        break
    fi
    sleep 1
done
if [ -z "$connected" ]; then
    docker logs "$container" >&2 || true
    fail "NATS did not accept TCP connections on 127.0.0.1:$port"
fi

docker logs "$container" 2>&1 | grep -q 'Server is ready' \
    || fail "NATS did not log 'Server is ready'"
pass "NATS listens on 127.0.0.1:$port and logs 'Server is ready'"

echo "== smoke test passed"
