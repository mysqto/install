#!/bin/bash
# wg-ss end-to-end test.
#
# Builds the real topology in docker and proves the container actually tunnels:
#
#   [sslocal] ──SS──▶ [wg-ss] ──wg0──▶ [wg server] ──▶ [nginx]
#    front net         front net        front + back        back net only
#
# The nginx target lives on a network wg-ss is NOT attached to, so fetching
# WGSS_TUNNEL_OK through the Shadowsocks proxy can only happen via the WireGuard
# tunnel. That single check covers the whole chain, including the return-path
# routing rule that inbound SS sessions depend on.
#
# Requires docker and a host kernel with WireGuard (the server side uses it).
set -uo pipefail

info() { echo -e "\033[1;36m== $*\033[0m"; }
ok()   { echo -e "\033[1;32mPASS: $*\033[0m"; }
bad()  { echo -e "\033[1;31mFAIL: $*\033[0m"; FAILED=1; }
warn() { echo -e "\033[1;33m$*\033[0m" >&2; }
FAILED=0

script_dir="$(cd "$(dirname "$0")" && pwd)"
image="wg-ss"
sstest_image="wg-ss-test-sslocal"
ss_version="1.25.0"

keep=""
recovery=""

usage() {
    cat <<EOF
Usage: $0 [options]

  --recovery   also test auto-recovery (kills the wireguard server and waits
               for the liveness probe to repair the tunnel; adds ~90s)
  --keep       leave the containers and networks running for inspection
  --cleanup    remove this test's containers/networks and exit
  --help       show this help
EOF
    exit 1
}

cleanup() {
    docker rm -f wgss-client wgss-server wgss-target wgss-sslocal >/dev/null 2>&1
    docker network rm wgss-front wgss-back >/dev/null 2>&1
    return 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --recovery) recovery="1"; shift ;;
        --keep)     keep="1"; shift ;;
        --cleanup)  cleanup; info "cleaned up"; exit 0 ;;
        --help|-h)  usage ;;
        *)          warn "unknown option: $1"; shift ;;
    esac
done

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
[ -n "$keep" ] || trap cleanup EXIT
cleanup

# ---------------------------------------------------------------------------
# images
# ---------------------------------------------------------------------------
if ! docker image inspect "$image" >/dev/null 2>&1; then
    info "building $image"
    docker build -t "$image" "$script_dir" >/dev/null || exit 1
fi

# An SS client to drive the proxy. shadowsocks-rust's own installer (used by the
# container) ships only ss-server, so pull sslocal from the upstream release.
if ! docker image inspect "$sstest_image" >/dev/null 2>&1; then
    info "building $sstest_image (sslocal $ss_version)"
    docker build -t "$sstest_image" - >/dev/null <<EOF || exit 1
FROM alpine:3.21
RUN apk add --no-cache curl xz ca-certificates
RUN set -e; \\
    case "\$(uname -m)" in x86_64) a=x86_64 ;; aarch64) a=aarch64 ;; *) echo "unsupported arch"; exit 1 ;; esac; \\
    curl -fsSL "https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${ss_version}/shadowsocks-v${ss_version}.\${a}-unknown-linux-musl.tar.xz" -o /tmp/ss.tar.xz; \\
    tar -xJf /tmp/ss.tar.xz -C /usr/local/bin sslocal; \\
    sslocal --version
EOF
fi

# ---------------------------------------------------------------------------
# topology
# ---------------------------------------------------------------------------
info "networks + target (back network only)"
docker network create --subnet 172.31.0.0/24 wgss-front >/dev/null || exit 1
docker network create --subnet 172.32.0.0/24 wgss-back  >/dev/null || exit 1
# alpine's busybox has no httpd applet, hence nginx
docker run -d --name wgss-target --network wgss-back --ip 172.32.0.20 nginx:alpine \
    sh -c 'echo WGSS_TUNNEL_OK > /usr/share/nginx/html/index.html && exec nginx -g "daemon off;"' >/dev/null || exit 1
sleep 2
docker inspect -f '{{.State.Status}}' wgss-target | grep -qx running \
    || { bad "target did not start"; docker logs wgss-target; exit 1; }

info "keypairs"
srv_priv=$(docker run --rm "$image" wg genkey)
srv_pub=$(printf '%s' "$srv_priv" | docker run --rm -i "$image" wg pubkey)
cli_priv=$(docker run --rm "$image" wg genkey)
cli_pub=$(printf '%s' "$cli_priv" | docker run --rm -i "$image" wg pubkey)

server_conf="[Interface]
PrivateKey = ${srv_priv}
Address = 10.99.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -s 10.99.0.0/24 -j MASQUERADE

[Peer]
PublicKey = ${cli_pub}
AllowedIPs = 10.99.0.2/32"

info "wireguard server (172.31.0.10, NATs 10.99.0.0/24 onto the back network)"
docker run -d --name wgss-server --network wgss-front --ip 172.31.0.10 \
    --cap-add NET_ADMIN --device /dev/net/tun \
    --sysctl net.ipv4.ip_forward=1 \
    -e CONF="$server_conf" "$image" \
    sh -c 'mkdir -p /etc/wireguard && printf "%s\n" "$CONF" > /etc/wireguard/wg0.conf && chmod 600 /etc/wireguard/wg0.conf && wg-quick up wg0 && exec sleep infinity' >/dev/null || exit 1
docker network connect --ip 172.32.0.10 wgss-back wgss-server || exit 1
sleep 4
docker exec wgss-server wg show wg0 >/dev/null 2>&1 \
    && ok "wg server up" || { bad "wg server did not come up"; docker logs wgss-server; exit 1; }

info "wg-ss (full tunnel, SS on 8388, obfs off for a plain client)"
docker run -d --name wgss-client --network wgss-front \
    --cap-add NET_ADMIN --device /dev/net/tun \
    --sysctl net.ipv4.conf.all.src_valid_mark=1 \
    -p 18388:8388/tcp -p 18388:8388/udp \
    -e WG_PRIVATE_KEY="$cli_priv" \
    -e WG_ADDRESS=10.99.0.2/24 \
    -e WG_PEER_PUBLIC_KEY="$srv_pub" \
    -e WG_ENDPOINT=172.31.0.10:51820 \
    -e WG_ALLOWED_IPS=0.0.0.0/0 \
    -e WG_PROBE_TARGET=10.99.0.1 \
    -e WG_PROBE_INTERVAL=10 \
    -e SS_OBFS=none \
    -e SS_PASSWORD=testpass123 \
    "$image" >/dev/null || exit 1
sleep 12
echo "---- wg-ss log ----"
docker logs wgss-client 2>&1 | grep -vE '^\[#\]' | tail -18
echo "-------------------"

# ---------------------------------------------------------------------------
# checks
# ---------------------------------------------------------------------------
docker exec wgss-client wg show wg0 >/dev/null 2>&1 \
    && ok "wg0 up in wg-ss" || bad "wg0 not up in wg-ss"
docker exec wgss-client ip rule list 2>/dev/null | grep -q '^90:' \
    && ok "return-path rule installed" || bad "return-path rule missing"
docker exec wgss-client ping -c1 -W3 -I wg0 10.99.0.1 >/dev/null 2>&1 \
    && ok "tunnel reaches the peer (10.99.0.1)" || bad "tunnel cannot reach the peer"
docker exec wgss-client sh -c 'ip route get 172.32.0.20 2>/dev/null | head -1' | grep -q wg0 \
    && ok "back-network traffic routes via wg0" || bad "back-network traffic does not route via wg0"

info "SS client -> wg-ss -> tunnel -> target on the back network"
docker run -d --name wgss-sslocal --network wgss-front "$sstest_image" \
    sh -c 'exec sslocal --local-addr 127.0.0.1:1080 --server-addr wgss-client:8388 \
        --password testpass123 --encrypt-method chacha20-ietf-poly1305 --protocol socks' >/dev/null || exit 1
sleep 3
fetch() { docker exec wgss-sslocal curl -s --max-time 15 --socks5-hostname 127.0.0.1:1080 http://172.32.0.20/ 2>&1; }
out=$(fetch)
if [ "$out" = "WGSS_TUNNEL_OK" ]; then
    ok "end-to-end: SS client fetched the tunnel-only target ($out)"
else
    bad "end-to-end fetch failed (got: '${out:-<empty/timeout>}')"
    docker logs wgss-sslocal 2>&1 | tail -10
fi

# The pref-90 rule only matters for replies to OFF-subnet clients, which is the
# real case: an external client DNATd in by docker keeps its own source address.
# suppress_prefixlength 0 hides only DEFAULT routes, so an SS client sitting on
# the container's own subnet works either way — a data-path test from this
# topology cannot see the difference. Compare route selection instead.
info "return-path rule: route chosen for a reply to an off-subnet client"
cip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' wgss-client)
with_rule=$(docker exec wgss-client ip route get 8.8.8.8 from "$cip" 2>/dev/null | head -1)
docker exec wgss-client ip rule del pref 90 >/dev/null 2>&1
without_rule=$(docker exec wgss-client ip route get 8.8.8.8 from "$cip" 2>/dev/null | head -1)
docker exec wgss-client ip rule add from "$cip" lookup main pref 90 >/dev/null 2>&1
echo "  with rule    : $with_rule"
echo "  without rule : $without_rule"
case "$with_rule" in
    *"dev eth0"*) ok "with the rule, replies leave via eth0" ;;
    *)            bad "with the rule, replies do not use eth0" ;;
esac
case "$without_rule" in
    *wg0*) ok "without the rule, replies would be lost into wg0" ;;
    *)     bad "without the rule the reply still used eth0 — rule may be unnecessary here" ;;
esac

if [ -n "$recovery" ]; then
    info "auto-recovery: killing the wireguard server"
    docker stop -t 1 wgss-server >/dev/null
    sleep 45
    logs=$(docker logs wgss-client 2>&1)
    case "$logs" in *"probe failed"*)   ok "probe detected the dead tunnel" ;; *) bad "probe did not detect the dead tunnel" ;; esac
    case "$logs" in *"restarting wg0"*) ok "tunnel restart attempted" ;;     *) bad "no tunnel restart attempted" ;; esac

    info "bringing the server back"
    docker start wgss-server >/dev/null
    sleep 40
    logs=$(docker logs wgss-client 2>&1)
    case "$logs" in *"wg0 recovered"*) ok "tunnel reported recovery" ;; *) bad "tunnel did not report recovery" ;; esac
    docker inspect -f '{{.State.Status}}' wgss-client | grep -qx running \
        && ok "container stayed up through the outage" || bad "container died during the outage"
    out=$(fetch)
    [ "$out" = "WGSS_TUNNEL_OK" ] \
        && ok "end-to-end works again after recovery" \
        || bad "end-to-end broken after recovery (got '${out:-<empty/timeout>}')"
fi

echo
if [ "$FAILED" = 0 ]; then
    echo -e "\033[1;32mALL TESTS PASSED\033[0m"
else
    echo -e "\033[1;31mSOME TESTS FAILED\033[0m"
fi
[ -n "$keep" ] && info "containers left running (./test-docker.sh --cleanup to remove)"
exit "$FAILED"
