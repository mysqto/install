# WireGuard client peer + Shadowsocks entry point.
#
# One container brings up a WireGuard *client* interface (kernel WireGuard when
# the host has the module, wireguard-go over /dev/net/tun otherwise) and exposes
# a shadowsocks-rust server (obfs-server plugin, same wire format as blackhole).
# Because ss-server dials targets from *inside* the container and the container's
# default route lives in the tunnel, external SS clients transparently egress
# through the WireGuard peer.

ARG ALPINE_VERSION=3.21

FROM alpine:${ALPINE_VERSION} AS builder

RUN apk add --no-cache \
    bash curl tar xz ca-certificates jq \
    git build-base autoconf automake libtool go \
    openssl-dev libev-dev pcre-dev zlib-dev linux-headers

# Install shadowsocks-rust (ss-server) + simple-obfs (obfs-server plugin),
# exactly like tailscale/blackhole — via the repo's own published installer.
RUN <<'EOF'
    set -e
    curl -fsSL https://debian.lol/ss-rust -o ss-rust.sh
    chmod +x ss-rust.sh
    ./ss-rust.sh
    rm -f ss-rust.sh
    /usr/local/bin/ss-server -V
    /usr/local/bin/obfs-server -h 2>&1 | head -n1 || true
EOF

# wireguard-go: userspace WireGuard, used when the host kernel has no wireguard
# module. Alpine does not package it, so build it from the upstream Go module.
# The main package sits at the module root, so `go install` names the binary
# "wireguard" — wg-quick wants "wireguard-go" on PATH.
# WIREGUARD_GO_VERSION: "latest", or a module version/pseudo-version to pin
# (upstream's 0.0.x git tags are NOT published to the module proxy).
ARG WIREGUARD_GO_VERSION=latest
RUN <<'EOF'
    set -e
    export GOBIN=/tmp/gobin CGO_ENABLED=0 GOFLAGS=-trimpath
    go install "golang.zx2c4.com/wireguard@${WIREGUARD_GO_VERSION:-latest}"
    install -m 0755 /tmp/gobin/wireguard /usr/local/bin/wireguard-go
    test -x /usr/local/bin/wireguard-go
EOF

# ---------------------------------------------------------------------------
ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION} AS application

COPY --from=builder /usr/local/bin/ss-server     /usr/local/bin/ss-server
COPY --from=builder /usr/local/bin/obfs-server   /usr/local/bin/obfs-server
COPY --from=builder /usr/local/bin/wireguard-go  /usr/local/bin/wireguard-go

# libev: simple-obfs runtime dep. wireguard-tools(-wg-quick): wg + wg-quick.
# iptables/iproute2: wg-quick's policy rules + kill switch for a default-route
# AllowedIPs. openresolv: wg-quick's DNS= handler — the entrypoint strips DNS=
# and applies it itself, this is only a safety net.
RUN apk add --no-cache \
    bash ca-certificates tzdata tini libev \
    wireguard-tools wireguard-tools-wg-quick openresolv \
    iptables ip6tables iproute2 curl jq pwgen

# /proc/sys is read-only in an unprivileged container, so wg-quick's
# `sysctl -q net.ipv4.conf.all.src_valid_mark=1` fails — and since wg-quick runs
# under `set -e`, that aborts the whole bring-up. This shim (earlier in PATH than
# /sbin) accepts a write whose value is ALREADY in effect, which is what
# `docker run --sysctl net.ipv4.conf.all.src_valid_mark=1` arranges, and fails
# loudly with the fix when it is not.
RUN <<'EOF'
    set -e
    cat > /usr/local/bin/sysctl <<'SHIM'
#!/bin/sh
real=/sbin/sysctl
[ -x "$real" ] || real=/usr/sbin/sysctl

# Reads pass straight through — only assignments can hit the read-only /proc/sys.
case " $* " in
    *=*) ;;
    *)   exec "$real" "$@" ;;
esac

# Attempt the write for real first, keeping its output so logs look normal.
out="$("$real" "$@" 2>&1)"
if [ $? -eq 0 ]; then
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 0
fi

rc=0
for arg in "$@"; do
    case "$arg" in
        -*)  continue ;;
        *=*) key="${arg%%=*}"; want="${arg#*=}" ;;
        *)   continue ;;
    esac
    key="$(printf '%s' "$key" | tr -d ' ')"
    want="$(printf '%s' "$want" | tr -d ' ')"
    have="$("$real" -n "$key" 2>/dev/null | tr -d ' \t')"
    [ "$have" = "$want" ] && continue
    echo "sysctl: cannot set ${key}=${want} — /proc/sys is read-only in this container (current: ${have:-unknown})" >&2
    echo "sysctl: add '--sysctl ${key}=${want}' to docker run" >&2
    rc=1
done
exit $rc
SHIM
    chmod +x /usr/local/bin/sysctl
EOF

# Rendered wg config (always overwritten at boot) and the ss-server config.
RUN mkdir -p /etc/wireguard /etc/shadowsocks /config
VOLUME /etc/wireguard

# --- WireGuard (client peer) ---
# Secrets (WG_PRIVATE_KEY, WG_PRESHARED_KEY, WG_CONFIG) are supplied at runtime
# with -e or a mounted /config/wg0.conf, never declared here.
ENV WG_IFACE=wg0 \
    WG_ADDRESS= \
    WG_ENDPOINT= \
    WG_PEER_PUBLIC_KEY= \
    WG_ALLOWED_IPS=0.0.0.0/0,::/0 \
    WG_MTU=1420 \
    WG_KEEPALIVE=25 \
    WG_TABLE= \
    WG_DNS= \
    WG_USE_DNS=true \
    WG_PROBE=true \
    WG_PROBE_TARGET= \
    WG_PROBE_INTERVAL=30 \
    WG_PROBE_FAILURES=3 \
    WG_HANDSHAKE_TIMEOUT=180 \
    WG_MAX_RESTARTS=5

# --- Shadowsocks (entry point for external clients) ---
# Secrets (SS_PASSWORD) are supplied at runtime with -e, never declared here.
ENV SS_PORT=8388 \
    SS_METHOD=chacha20-ietf-poly1305 \
    SS_MODE=tcp_and_udp \
    SS_OBFS=http \
    SS_OBFS_HOST=

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/docker-entrypoint.sh"]
