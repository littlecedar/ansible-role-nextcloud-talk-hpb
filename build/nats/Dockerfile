# syntax=docker/dockerfile:1

# SPDX-FileCopyrightText: 2026 Travis Wichert
#
# SPDX-License-Identifier: AGPL-3.0-or-later

ARG GO_VERSION=1.26.8
ARG NATS_VERSION=2.15.1
ARG NATS_COMMIT=b2fd3efc7456b11b06a54877ad6f6ccfb911edb4

FROM golang:${GO_VERSION}-alpine AS builder
ARG NATS_VERSION
ARG NATS_COMMIT
RUN apk add --no-cache ca-certificates git \
 && git clone --depth 1 --branch "v${NATS_VERSION}" \
      https://github.com/nats-io/nats-server.git /src \
 && test "$(git -C /src rev-parse HEAD)" = "${NATS_COMMIT}"
WORKDIR /src
RUN CGO_ENABLED=0 go build -trimpath \
      -ldflags "-s -w \
        -X github.com/nats-io/nats-server/v2/server.serverVersion=v${NATS_VERSION} \
        -X github.com/nats-io/nats-server/v2/server.gitCommit=${NATS_COMMIT}" \
      -o /out/nats-server . \
 && mkdir -p /out/empty

FROM scratch AS runtime
ARG NATS_VERSION
ARG NATS_COMMIT

LABEL org.opencontainers.image.title="ansible-role-nextcloud-talk-hpb-nats" \
      org.opencontainers.image.description="NATS server for Nextcloud Talk HPB" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${NATS_VERSION}" \
      org.opencontainers.image.revision="${NATS_COMMIT}"

COPY --from=builder /out/nats-server /usr/local/bin/nats-server
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /out/empty /tmp
COPY --from=builder /out/empty /etc/nats

USER 1000:1000
EXPOSE 4222
ENTRYPOINT ["/usr/local/bin/nats-server"]
