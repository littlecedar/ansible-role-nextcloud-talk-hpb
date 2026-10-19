#!/bin/sh

# SPDX-FileCopyrightText: 2026 Travis Wichert
#
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu
umask 077

defaults=/opt/janus/etc/janus
runtime_dir=/tmp/janus-config
overrides="${JANUS_OVERRIDE_DIR:-/etc/janus.d}"

rm -rf "$runtime_dir"
mkdir -p "$runtime_dir"
cp -R "$defaults"/. "$runtime_dir"/

if [ -d "$overrides" ]; then
    for file in "$overrides"/*.jcfg; do
        [ -f "$file" ] || continue
        name=${file##*/}
        if [ ! -f "$runtime_dir/$name" ]; then
            echo "janus-entrypoint: WARNING '$name' matches no stock config" >&2
        fi
        cp "$file" "$runtime_dir/$name"
        echo "janus-entrypoint: applied override $name"
    done
fi

http_ip="${JANUS_HTTP_IP:-127.0.0.1}"
http_port="${JANUS_HTTP_PORT:-8088}"
http_acl="${JANUS_HTTP_ACL:-127.0.0.1}"
ws_ip="${JANUS_WS_IP:-127.0.0.1}"
ws_port="${JANUS_WS_PORT:-8188}"
ws_acl="${JANUS_WS_ACL:-127.0.0.1}"

sed -i \
  -e 's/^[[:space:]]*#\?[[:space:]]*http[[:space:]]*=.*/http = true/' \
  -e 's/^[[:space:]]*#\?[[:space:]]*https[[:space:]]*=.*/https = false/' \
  -e "s/^[[:space:]]*#\?[[:space:]]*port[[:space:]]*=.*/port = ${http_port}/" \
  -e "s|^[[:space:]]*#\?[[:space:]]*ip[[:space:]]*=.*|ip = \"${http_ip}\"|" \
  -e "s|^[[:space:]]*#\?[[:space:]]*acl[[:space:]]*=.*|acl = \"${http_acl}\"|" \
  -e 's/^[[:space:]]*admin_http[[:space:]]*=.*/admin_http = false/' \
  "$runtime_dir/janus.transport.http.jcfg"

sed -i \
  -e 's/^[[:space:]]*#\?[[:space:]]*ws[[:space:]]*=.*/ws = true/' \
  -e 's/^[[:space:]]*#\?[[:space:]]*wss[[:space:]]*=.*/wss = false/' \
  -e "s/^[[:space:]]*#\?[[:space:]]*ws_port[[:space:]]*=.*/ws_port = ${ws_port}/" \
  -e "s|^[[:space:]]*#\?[[:space:]]*ws_ip[[:space:]]*=.*|ws_ip = \"${ws_ip}\"|" \
  -e "s|^[[:space:]]*#\?[[:space:]]*ws_acl[[:space:]]*=.*|ws_acl = \"${ws_acl}\"|" \
  -e 's/^[[:space:]]*admin_ws[[:space:]]*=.*/admin_ws = false/' \
  "$runtime_dir/janus.transport.websockets.jcfg"

if [ -n "${JANUS_EVENT_BACKEND:-}" ]; then
    sed -i 's/^[[:space:]]*#\?[[:space:]]*broadcast[[:space:]]*=.*/broadcast = true/' \
      "$runtime_dir/janus.jcfg"
    sed -i \
      -e 's/^[[:space:]]*#\?[[:space:]]*enabled[[:space:]]*=.*/enabled = true/' \
      -e "s|^[[:space:]]*#\?[[:space:]]*backend[[:space:]]*=.*|backend = \"${JANUS_EVENT_BACKEND}\"|" \
      -e 's/^[[:space:]]*#\?[[:space:]]*subprotocol[[:space:]]*=.*/subprotocol = "janus-events"/' \
      -e 's/^[[:space:]]*#\?[[:space:]]*events[[:space:]]*=.*/events = "handles,media,webrtc"/' \
      -e 's/^[[:space:]]*#\?[[:space:]]*events_cap_on_reconnect[[:space:]]*=.*/events_cap_on_reconnect = 100/' \
      -e 's/^[[:space:]]*#\?[[:space:]]*events_max_queue[[:space:]]*=.*/events_max_queue = 20000/' \
      "$runtime_dir/janus.eventhandler.wsevh.jcfg"
    echo "janus-entrypoint: events backend ${JANUS_EVENT_BACKEND}"
fi

if [ -n "${JANUS_TURN_SERVER:-}" ]; then
    turn_port="${JANUS_TURN_PORT:-3478}"
    turn_type="${JANUS_TURN_TYPE:-udp}"
    if [ -n "${JANUS_TURN_USER:-}" ] && [ -n "${JANUS_TURN_PWD:-}" ]; then
        turn_user="$JANUS_TURN_USER"
        turn_pwd="$JANUS_TURN_PWD"
    elif [ -n "${JANUS_TURN_SECRET:-}" ]; then
        turn_user="$(( $(date +%s) + 7776000 )):$(openssl rand -hex 16)"
        turn_pwd=$(printf '%s' "$turn_user" | openssl dgst -sha1 -hmac "$JANUS_TURN_SECRET" -binary | openssl base64)
    else
        echo "janus-entrypoint: JANUS_TURN_SERVER requires JANUS_TURN_SECRET or JANUS_TURN_USER/JANUS_TURN_PWD" >&2
        exit 1
    fi
    sed -i '/^nat:[[:space:]]*{/,/^}/d' "$runtime_dir/janus.jcfg"
    {
        printf '\nnat: {\n'
        printf '\tturn_server = "%s"\n' "$JANUS_TURN_SERVER"
        printf '\tturn_port = %s\n' "$turn_port"
        printf '\tturn_type = "%s"\n' "$turn_type"
        printf '\tturn_user = "%s"\n' "$turn_user"
        printf '\tturn_pwd = "%s"\n' "$turn_pwd"
        if [ -n "${JANUS_NAT_1_1_MAPPING:-}" ]; then
            printf '\tnat_1_1_mapping = "%s"\n' "$JANUS_NAT_1_1_MAPPING"
        fi
        if [ -n "${JANUS_RTP_PORT_RANGE:-}" ]; then
            printf '\trtp_port_range = "%s"\n' "$JANUS_RTP_PORT_RANGE"
        fi
        if [ -n "${JANUS_ICE_IGNORE_LIST:-}" ]; then
            printf '\tice_ignore_list = "%s"\n' "$JANUS_ICE_IGNORE_LIST"
        fi
        if [ -n "${JANUS_ICE_ENFORCE_LIST:-}" ]; then
            printf '\tice_enforce_list = "%s"\n' "$JANUS_ICE_ENFORCE_LIST"
        fi
        printf '}\n'
    } >> "$runtime_dir/janus.jcfg"
    echo "janus-entrypoint: TURN ${JANUS_TURN_SERVER}:${turn_port} (ephemeral credentials)"
    unset JANUS_TURN_SECRET JANUS_TURN_USER JANUS_TURN_PWD turn_user turn_pwd
fi

sed -i '/^room-1234:[[:space:]]*{/,/^}/d' "$runtime_dir/janus.plugin.videoroom.jcfg"

exec "$@"
