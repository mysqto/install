# ss2any — Shadowsocks inbound, "any" outbound (VLESS/Trojan/VMess/Hysteria2/TUIC/SS).
# One process (sing-box), one tiny Python parser, one Alpine layer.

ARG ALPINE_VERSION=3.21
ARG SING_BOX_VERSION=1.10.7

FROM alpine:${ALPINE_VERSION} AS fetcher

ARG SING_BOX_VERSION
ARG TARGETARCH

RUN apk add --no-cache curl tar ca-certificates \
    git build-base autoconf automake libtool \
    openssl-dev libev-dev pcre-dev linux-headers

RUN <<EOF
    set -eu
    arch=$(uname -m)
    case "$arch" in
        x86_64)  sb_arch=amd64 ;;
        aarch64) sb_arch=arm64 ;;
        armv7l)  sb_arch=armv7 ;;
        *) echo "Unsupported architecture: $arch" >&2 ; exit 1 ;;
    esac
    url="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${sb_arch}.tar.gz"
    echo "Fetching: $url"
    curl -fsSL "$url" -o /tmp/sb.tar.gz
    mkdir -p /tmp/sb
    tar -xzf /tmp/sb.tar.gz -C /tmp/sb --strip-components=1
    install -m 0755 /tmp/sb/sing-box /usr/local/bin/sing-box
    /usr/local/bin/sing-box version
EOF

# Build simple-obfs so that the SS inbound can use plugin=obfs-server, keeping
# wire compatibility with shadowsocks-libev's HTTP/TLS obfuscation.
RUN <<EOF
    set -eu
    git clone --depth 1 https://github.com/shadowsocks/simple-obfs.git /tmp/simple-obfs
    cd /tmp/simple-obfs
    git submodule update --init --recursive
    ./autogen.sh
    ./configure --disable-documentation --prefix=/usr/local
    make -j"$(nproc 2>/dev/null || echo 4)"
    make install
    /usr/local/bin/obfs-server -h 2>&1 | head -n1 || true
EOF

ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION} AS application

COPY --from=fetcher /usr/local/bin/sing-box     /usr/local/bin/sing-box
COPY --from=fetcher /usr/local/bin/obfs-server  /usr/local/bin/obfs-server
COPY --from=fetcher /usr/local/bin/obfs-local   /usr/local/bin/obfs-local

# `libev` is simple-obfs's only runtime dep.
RUN apk add --no-cache bash python3 py3-yaml ca-certificates tzdata tini libev

RUN mkdir -p /config
VOLUME /config

ENV SS_PORT=8388 \
    SS_METHOD=chacha20-ietf-poly1305 \
    SS_PASSWORD= \
    SS_NETWORK=tcp \
    SS_OBFS_HOST= \
    SS_OBFS_MODE=http \
    PROXY_LINK= \
    PROXY_LINK_FILE=/config/proxy.link \
    LOG_LEVEL=info

COPY generate-config.py /usr/local/bin/generate-config.py
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/generate-config.py /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/docker-entrypoint.sh"]
