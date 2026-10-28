#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Travis Wichert
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Image behavior smoke test for the Nextcloud Talk signaling container.
set -euo pipefail

image="${1:-nextcloud-talk-hpb-spreed:local}"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
dockerfile="${DOCKERFILE:-$repo_root/build/spreed/Dockerfile}"

expected_version=$(sed -n 's/^ARG SPREED_VERSION=\(.*\)$/\1/p' "$dockerfile" | head -n 1)
if [ -z "$expected_version" ]; then
    echo "could not parse SPREED_VERSION from $dockerfile" >&2
    exit 1
fi

container="spreed-smoke-$$"
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

echo "== image: $image (expected nextcloud-spreed-signaling $expected_version)"

# --- 1. image metadata -------------------------------------------------------
[ "$(docker image inspect --format '{{.Config.User}}' "$image")" = "1000:1000" ] \
    || fail "image user is not 1000:1000"
if docker run --rm --entrypoint /bin/sh "$image" -c true >/dev/null 2>&1; then
    fail "/bin/sh is present (the runtime must be shell-free)"
fi
pass "user 1000:1000, no /bin/sh"

# --- 2. compiled version -----------------------------------------------------
version_output=$(docker run --rm --entrypoint /usr/bin/nextcloud-spreed-signaling "$image" -version 2>&1)
printf '%s\n' "$version_output" | grep -qF "version $expected_version/" \
    || fail "nextcloud-spreed-signaling -version does not report $expected_version"
pass "nextcloud-spreed-signaling -version reports $expected_version"

# --- 3. start the container --------------------------------------------------
config="$tmp_dir/server.conf"
cat > "$config" <<'EOF'
[http]
listen = 0.0.0.0:8081

[sessions]
hashkey = 0123456789abcdef0123456789abcdef

[clients]
internalsecret = smoke

[nats]
url = nats://loopback

[backend]
backends = nextcloud
allowall = true

[nextcloud]
urls = https://example.invalid
secret = smoke

[stats]
allowed_ips = 127.0.0.1
EOF
chmod 644 "$config"

docker run -d --name "$container" \
    --read-only \
    --tmpfs /tmp \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --user 1000:1000 \
    -v "$config:/etc/signaling/server.conf:ro" \
    -p 127.0.0.1::8081 \
    "$image" -config /etc/signaling/server.conf >/dev/null

port=""
ready=""
for _ in $(seq 1 30); do
    port=$(docker port "$container" 8081/tcp 2>/dev/null | head -n 1 | sed 's/.*://')
    if [ -n "$port" ] && curl -fsS "http://127.0.0.1:$port/api/v1/welcome" >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done
if [ -z "$ready" ]; then
    docker logs "$container" >&2 || true
    fail "signaling HTTP API did not answer on 127.0.0.1:${port:-<unpublished>}"
fi
pass "signaling answers on the loopback HTTP API"

# --- 4. graceful shutdown ----------------------------------------------------
docker stop "$container" >/dev/null
# docker stop returns when the process exits, which can be before the log
# copier has flushed the shutdown line; give it a bounded moment to appear.
shutdown_log=""
for _ in $(seq 1 10); do
    shutdown_log=$(docker logs "$container" 2>&1 || true)
    case "$shutdown_log" in
        *'Received SIGUSR1'*) break ;;
    esac
    sleep 1
done
case "$shutdown_log" in
    *'Received SIGUSR1'*) ;;
    *)
        printf '%s\n' "$shutdown_log" >&2
        fail "signaling did not log 'Received SIGUSR1' on docker stop"
        ;;
esac
pass "docker stop delivers SIGUSR1 and the server shuts down"

echo "== smoke test passed"
