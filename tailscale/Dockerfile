# Tailscale node + Shadowsocks entry point.
#
# One container joins your tailnet (kernel-mode tailscaled over /dev/net/tun)
# and exposes a shadowsocks-rust server (obfs-server plugin, same wire format
# as blackhole). Because ss-server dials targets from *inside* the container,
# and the node runs with --accept-routes, external SS clients transparently
# reach the container, tailnet IPs (100.64.0.0/10), and advertised subnets.

ARG ALPINE_VERSION=3.21

FROM alpine:${ALPINE_VERSION} AS builder

# TAILSCALE_VERSION: pin a release, or leave "latest" to resolve stable at build.
ARG TAILSCALE_VERSION=latest

RUN apk add --no-cache \
    bash curl tar xz ca-certificates jq \
    git build-base autoconf automake libtool \
    openssl-dev libev-dev pcre-dev zlib-dev linux-headers

# Install shadowsocks-rust (ss-server) + simple-obfs (obfs-server plugin),
# exactly like blackhole — via the repo's own published installer.
RUN <<'EOF'
    set -e
    curl -fsSL https://debian.lol/ss-rust -o ss-rust.sh
    chmod +x ss-rust.sh
    ./ss-rust.sh
    rm -f ss-rust.sh
    /usr/local/bin/ss-server -V
    /usr/local/bin/obfs-server -h 2>&1 | head -n1 || true
EOF

# Fetch the static tailscale + tailscaled binaries for this architecture.
ARG TAILSCALE_VERSION
RUN <<'EOF'
    set -e
    case "$(uname -m)" in
        x86_64)  ts_arch=amd64 ;;
        aarch64) ts_arch=arm64 ;;
        armv7l)  ts_arch=arm   ;;
        i386|i686) ts_arch=386 ;;
        *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
    esac

    ver="${TAILSCALE_VERSION}"
    if [ -z "$ver" ] || [ "$ver" = "latest" ]; then
        ver=$(curl -fsSL 'https://pkgs.tailscale.com/stable/?mode=json' | jq -r '.Version')
    fi
    [ -z "$ver" ] || [ "$ver" = "null" ] && { echo "failed to resolve tailscale version" >&2; exit 1; }

    tarball="tailscale_${ver}_${ts_arch}.tgz"
    url="https://pkgs.tailscale.com/stable/${tarball}"
    echo "Fetching: $url"
    curl -fsSL "$url" -o /tmp/ts.tgz
    mkdir -p /tmp/ts
    tar -xzf /tmp/ts.tgz -C /tmp/ts --strip-components=1
    install -m 0755 /tmp/ts/tailscale  /usr/local/bin/tailscale
    install -m 0755 /tmp/ts/tailscaled /usr/local/bin/tailscaled
    /usr/local/bin/tailscale --version
EOF

# ---------------------------------------------------------------------------
ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION} AS application

COPY --from=builder /usr/local/bin/ss-server    /usr/local/bin/ss-server
COPY --from=builder /usr/local/bin/obfs-server  /usr/local/bin/obfs-server
COPY --from=builder /usr/local/bin/tailscale    /usr/local/bin/tailscale
COPY --from=builder /usr/local/bin/tailscaled   /usr/local/bin/tailscaled

# libev: simple-obfs runtime dep. iptables/iproute2: tailscale subnet routing.
RUN apk add --no-cache \
    bash ca-certificates tzdata tini libev \
    iptables ip6tables iproute2 curl jq pwgen

# tailscaled state (persist across restarts) and ss-server config.
RUN mkdir -p /var/lib/tailscale /var/run/tailscale /etc/shadowsocks
VOLUME /var/lib/tailscale

# --- Tailscale ---
ENV TS_AUTHKEY= \
    TS_HOSTNAME= \
    TS_ROUTES= \
    TS_ACCEPT_ROUTES=true \
    TS_ACCEPT_DNS=false \
    TS_ADVERTISE_EXIT_NODE=false \
    TS_EXIT_NODE= \
    TS_EXTRA_ARGS= \
    TS_STATE_DIR=/var/lib/tailscale \
    TS_SOCKET=/var/run/tailscale/tailscaled.sock \
    TS_TUN=tailscale0 \
    TS_PORT=41641

# --- Shadowsocks (entry point for external clients) ---
ENV SS_PORT=8388 \
    SS_PASSWORD= \
    SS_METHOD=chacha20-ietf-poly1305 \
    SS_MODE=tcp_and_udp \
    SS_OBFS=http \
    SS_OBFS_HOST=

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/docker-entrypoint.sh"]
