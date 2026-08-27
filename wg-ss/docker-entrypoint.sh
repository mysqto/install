#!/bin/bash
# WireGuard client peer + Shadowsocks entry point.
#
# Brings up a WireGuard client interface (kernel WireGuard, wireguard-go
# fallback), then runs a shadowsocks-rust server that external clients use to
# egress through the tunnel. ss-server dials every target from inside the
# container, so whatever the tunnel routes, SS clients reach.
set -uo pipefail

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
info()  { echo -e "\033[32m[$(timestamp)] INFO: $*\033[0m"; }
warn()  { echo -e "\033[33m[$(timestamp)] WARN: $*\033[0m" >&2; }
error() { echo -e "\033[31m[$(timestamp)] ERROR: $*\033[0m" >&2; exit 1; }

WG_IFACE="${WG_IFACE:-wg0}"
WG_DIR=/etc/wireguard
WG_CONF="${WG_DIR}/${WG_IFACE}.conf"
MOUNTED_CONF=/config/wg0.conf
RETURN_RULE_PREF=90

SS_PID=""
WG_UP=""
WG_DNS_SERVERS=""
WG_FULL_TUNNEL=""
PROBE_TARGET=""
CONFIG_SOURCE=""

shutdown() {
    info "shutting down..."
    [ -n "$SS_PID" ] && kill -TERM "$SS_PID" 2>/dev/null || true
    [ -n "$WG_UP" ] && wg-quick down "$WG_IFACE" >/dev/null 2>&1 || true
    wait 2>/dev/null || true
}
trap shutdown TERM INT HUP

# Strip an inline "# comment" and surrounding whitespace. docker --env-file does
# NOT honor inline comments, so a value like "10.0.0.2/32   # note" arrives
# literally; sanitize the constrained fields so a stray comment can't corrupt
# the generated config. (Not applied to keys or SS_PASSWORD, which are opaque.)
_clean() {
    local v="${1%%#*}"                 # drop inline comment
    v="${v#"${v%%[![:space:]]*}"}"     # ltrim
    v="${v%"${v##*[![:space:]]}"}"     # rtrim
    printf '%s' "$v"
}

# ---------------------------------------------------------------------------
# config: mounted file > WG_CONFIG > discrete WG_* variables
# ---------------------------------------------------------------------------
# A rejected config is almost always a mangled paste — or a base64 of one, where
# the damage is invisible until someone decodes it by hand. Show what actually
# landed in the file instead of only what was missing.
config_invalid() {
    warn "$WG_CONF is not a valid WireGuard config: $1"
    warn "  source      : ${CONFIG_SOURCE:-unknown}"
    warn "  size        : $(wc -c <"$WG_CONF" | tr -d ' ') bytes, $(wc -l <"$WG_CONF" | tr -d ' ') lines"
    warn "  first line  : \"$(head -n1 "$WG_CONF" | cut -c1-60)\""
    warn "  sections    : $(grep -oE '^[[:space:]]*\[[A-Za-z]+\]' "$WG_CONF" 2>/dev/null | tr -d ' ' | tr '\n' ' ')"
    warn "  directives  : $(grep -oiE '^[[:space:]]*[A-Za-z]+[[:space:]]*=' "$WG_CONF" 2>/dev/null | tr -d ' =' | tr '\n' ' ')"
    warn "  a valid config starts with the literal line: [Interface]"
    error "fix the config source, then recreate the container (a restart reuses the old environment)"
}

render_from_env() {
    local addr key peer endpoint allowed mtu keepalive psk
    addr="$(_clean "${WG_ADDRESS:-}")"
    peer="$(_clean "${WG_PEER_PUBLIC_KEY:-}")"
    endpoint="$(_clean "${WG_ENDPOINT:-}")"
    allowed="$(_clean "${WG_ALLOWED_IPS:-0.0.0.0/0,::/0}")"
    mtu="$(_clean "${WG_MTU:-1420}")"
    keepalive="$(_clean "${WG_KEEPALIVE:-25}")"
    key="${WG_PRIVATE_KEY:-}"
    psk="${WG_PRESHARED_KEY:-}"

    [ -z "$key" ] && error "no WireGuard config: mount $MOUNTED_CONF, set WG_CONFIG, or set WG_PRIVATE_KEY + WG_ADDRESS + WG_PEER_PUBLIC_KEY + WG_ENDPOINT"
    [ -z "$addr" ]     && error "WG_ADDRESS is required (e.g. 10.0.0.2/32)"
    [ -z "$peer" ]     && error "WG_PEER_PUBLIC_KEY is required"
    [ -z "$endpoint" ] && error "WG_ENDPOINT is required (host:port)"

    info "rendering $WG_CONF from WG_* variables"
    {
        echo "[Interface]"
        echo "PrivateKey = ${key}"
        echo "Address = ${addr}"
        [ -n "$mtu" ] && echo "MTU = ${mtu}"
        echo ""
        echo "[Peer]"
        echo "PublicKey = ${peer}"
        [ -n "$psk" ] && echo "PresharedKey = ${psk}"
        echo "Endpoint = ${endpoint}"
        echo "AllowedIPs = ${allowed}"
        [ -n "$keepalive" ] && echo "PersistentKeepalive = ${keepalive}"
    } > "$WG_CONF"
}

render_wg_config() {
    mkdir -p "$WG_DIR"
    if [ -f "$MOUNTED_CONF" ]; then
        info "using mounted config: $MOUNTED_CONF"
        CONFIG_SOURCE="mounted file $MOUNTED_CONF"
        cat "$MOUNTED_CONF" > "$WG_CONF" || error "could not read $MOUNTED_CONF"
    elif [ -n "${WG_CONFIG:-}" ]; then
        info "using WG_CONFIG from the environment"
        CONFIG_SOURCE="WG_CONFIG environment variable"
        if printf '%s' "$WG_CONFIG" | grep -q '\['; then
            # raw config; "\n" escapes are expanded so it survives a single -e
            printf '%b\n' "$WG_CONFIG" > "$WG_CONF"
        else
            CONFIG_SOURCE="WG_CONFIG environment variable (base64)"
            printf '%s' "$WG_CONFIG" | tr -d ' \n' | base64 -d > "$WG_CONF" \
                || error "WG_CONFIG is neither a WireGuard config nor valid base64"
        fi
    elif [ -n "${WG_PRIVATE_KEY:-}" ]; then
        render_from_env
    elif [ -s "$WG_CONF" ]; then
        # the /etc/wireguard volume persists the last config, so a restart or a
        # re-create does not need the key passed in again
        info "reusing the config persisted at $WG_CONF (nothing supplied this run)"
        CONFIG_SOURCE="$WG_CONF persisted in the volume"
    else
        error "no WireGuard config: mount $MOUNTED_CONF, set WG_CONFIG, or set WG_PRIVATE_KEY + WG_ADDRESS + WG_PEER_PUBLIC_KEY + WG_ENDPOINT"
    fi
    chmod 600 "$WG_CONF"

    grep -qiE '^[[:space:]]*\[Interface\]' "$WG_CONF" || config_invalid "no [Interface] section"
    grep -qiE '^[[:space:]]*PrivateKey[[:space:]]*=' "$WG_CONF" || config_invalid "no PrivateKey"
    grep -qiE '^[[:space:]]*\[Peer\]' "$WG_CONF" || config_invalid "no [Peer] section"
    grep -qiE '^[[:space:]]*Endpoint[[:space:]]*=' "$WG_CONF" || warn "$WG_CONF has no Endpoint — this peer can only be reached if it dials us"
}

# Take DNS= out of the config (wg-quick's handler needs resolvconf and rewrites
# /etc/resolv.conf, which is a bind mount in a container — we do it ourselves in
# apply_dns), honor WG_TABLE, and note whether this is a full tunnel.
prepare_conf() {
    local dns d table
    dns="$(grep -iE '^[[:space:]]*DNS[[:space:]]*=' "$WG_CONF" | head -n1 | cut -d= -f2- | tr -d ' ' | tr ',' ' ')"
    [ -n "${WG_DNS:-}" ] && dns="$(_clean "${WG_DNS}" | tr ',' ' ')"
    for d in $dns; do
        # DNS= may also carry search domains; keep only addresses
        case "$d" in
            *[0-9].[0-9]*|*:*) WG_DNS_SERVERS="${WG_DNS_SERVERS:+$WG_DNS_SERVERS }$d" ;;
        esac
    done
    sed -i -E '/^[[:space:]]*[Dd][Nn][Ss][[:space:]]*=/d' "$WG_CONF"

    table="$(_clean "${WG_TABLE:-}")"
    if [ -n "$table" ]; then
        sed -i -E '/^[[:space:]]*[Tt]able[[:space:]]*=/d' "$WG_CONF"
        awk -v t="$table" '
            { print }
            !done && tolower($0) ~ /^[[:space:]]*\[interface\][[:space:]]*$/ { print "Table = " t; done = 1 }
        ' "$WG_CONF" > "${WG_CONF}.tmp" && mv "${WG_CONF}.tmp" "$WG_CONF"
        chmod 600 "$WG_CONF"
        warn "Table = $table — wg-quick will not manage routes; routing is yours to arrange"
    fi

    if grep -iE '^[[:space:]]*AllowedIPs[[:space:]]*=' "$WG_CONF" \
        | grep -qE '(^|[=, ])(0\.0\.0\.0/0|::/0)([, ]|$)'; then
        WG_FULL_TUNNEL=1
        info "AllowedIPs is a default route — all ss-server egress goes through $WG_IFACE"
    fi
}

apply_dns() {
    local s
    [ "$(_clean "${WG_USE_DNS:-true}")" = "true" ] || { info "WG_USE_DNS=false — keeping the container resolver"; return; }
    [ -z "$WG_DNS_SERVERS" ] && { info "no tunnel DNS configured — keeping the container resolver"; return; }
    # /etc/resolv.conf is a docker bind mount: truncate in place, never replace.
    {
        for s in $WG_DNS_SERVERS; do echo "nameserver $s"; done
        echo "options timeout:2 attempts:2"
    } > /etc/resolv.conf 2>/dev/null || { warn "could not write /etc/resolv.conf"; return; }
    info "resolver set to tunnel DNS: $WG_DNS_SERVERS"
}

# ---------------------------------------------------------------------------
# wireguard
# ---------------------------------------------------------------------------
# Kernel WireGuard or wireguard-go? wg-quick decides that itself: it tries
# `ip link add type wireguard` and only falls back to
# WG_QUICK_USERSPACE_IMPLEMENTATION when that fails. All we do here is find out
# which way it will go, so the log says so, and make sure the prerequisites of
# the userspace path are in place before wg-quick needs them.
probe_wg_mode() {
    if ip link add dev wgprobe0 type wireguard 2>/dev/null; then
        ip link del dev wgprobe0 2>/dev/null || true
        info "using kernel WireGuard"
        return 0
    fi
    warn "host kernel has no wireguard module — falling back to wireguard-go (userspace)"

    if [ ! -c /dev/net/tun ]; then
        warn "/dev/net/tun missing — attempting to create it"
        mkdir -p /dev/net
        if mknod /dev/net/tun c 10 200 2>/dev/null; then
            chmod 600 /dev/net/tun
            info "created /dev/net/tun"
        fi
    fi
    [ -c /dev/net/tun ] || error "no kernel WireGuard and no /dev/net/tun — run with --device /dev/net/tun --cap-add NET_ADMIN"
    command -v wireguard-go >/dev/null 2>&1 || error "no kernel WireGuard and wireguard-go is missing from the image"
    export WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go
}

# wg-quick's default-route setup installs `ip rule` entries (pref 32764/32765)
# that pull ALL traffic into the tunnel. Replies to INBOUND connections — the SS
# clients — would then leave via the tunnel with the wrong source address, and
# every session would hang right after the TCP handshake. Pin traffic already
# sourced from a local non-tunnel address to the main table, ahead of those
# rules. Locally *originated* connections are unaffected: their source is not
# chosen until after the route lookup, so they still take the tunnel.
fix_return_routing() {
    local fam addr
    for fam in -4 -6; do
        while read -r addr; do
            [ -z "$addr" ] && continue
            ip "$fam" rule list 2>/dev/null | grep -q "from ${addr} lookup main" && continue
            if ip "$fam" rule add from "$addr" lookup main pref "$RETURN_RULE_PREF" 2>/dev/null; then
                info "return-path rule: from $addr lookup main (pref $RETURN_RULE_PREF)"
            fi
        done < <(ip "$fam" -o addr show scope global 2>/dev/null \
                    | awk -v ifc="$WG_IFACE" '$2 != ifc { split($4, a, "/"); print a[1] }')
    done
}

start_wireguard() {
    info "bringing up $WG_IFACE ..."
    wg-quick up "$WG_IFACE" || error "wg-quick up $WG_IFACE failed"
    WG_UP=1
    fix_return_routing

    local ep addrs
    ep="$(wg show "$WG_IFACE" endpoints 2>/dev/null | awk '{print $2}' | head -n1)"
    addrs="$(ip -o addr show dev "$WG_IFACE" scope global 2>/dev/null | awk '{print $4}' | tr '\n' ' ')"
    info "$WG_IFACE is up (address: ${addrs:-none}, peer endpoint: ${ep:-unresolved})"
}

restart_wireguard() {
    warn "restarting $WG_IFACE ..."
    wg-quick down "$WG_IFACE" >/dev/null 2>&1 || true
    sleep 2
    if ! wg-quick up "$WG_IFACE"; then
        warn "wg-quick up failed during restart"
        return 1
    fi
    fix_return_routing
    apply_dns
    info "$WG_IFACE restarted"
    return 0
}

# ---------------------------------------------------------------------------
# liveness probe
# ---------------------------------------------------------------------------
# Age in seconds of the most recent handshake; -1 when there has never been one.
handshake_age() {
    local now newest
    now="$(date +%s)"
    newest="$(wg show "$WG_IFACE" latest-handshakes 2>/dev/null | awk '{ if ($2+0 > m) m = $2+0 } END { print m+0 }')"
    [ -z "$newest" ] && newest=0
    if [ "$newest" -le 0 ]; then echo -1; else echo $(( now - newest )); fi
}

# The peer's own address inside the tunnel — network+1 of our tunnel address.
# Pinging that tests the tunnel and nothing else; a public target like 1.1.1.1
# additionally depends on the peer routing egress for us and answering ICMP from
# a third party, so it reports a healthy tunnel as dead.
derive_tunnel_gateway() {
    local cidr base prefix gw
    cidr="$(ip -o -4 addr show dev "$WG_IFACE" scope global 2>/dev/null | awk '{print $4}' | head -n1)"
    [ -z "$cidr" ] && return 1
    base="${cidr%/*}"; prefix="${cidr#*/}"
    case "$prefix" in ''|*[!0-9]*) return 1 ;; esac
    # /31 and /32 carry no usable gateway; very short prefixes are not a LAN
    [ "$prefix" -lt 8 ] && return 1
    [ "$prefix" -gt 30 ] && return 1
    # awk has no portable bitwise AND: net = ip - (ip mod hostcount)
    gw="$(printf '%s' "$base" | awk -F. -v p="$prefix" '
        {
            ip = ($1 * 16777216) + ($2 * 65536) + ($3 * 256) + $4
            size = 2 ^ (32 - p)
            g = (ip - (ip % size)) + 1
            printf "%d.%d.%d.%d", int(g/16777216)%256, int(g/65536)%256, int(g/256)%256, g%256
        }')"
    # if that is us, pinging it would always succeed and prove nothing
    [ -z "$gw" ] || [ "$gw" = "$base" ] && return 1
    printf '%s' "$gw"
}

# A ping through the tunnel is the only signal that distinguishes "idle" from
# "dead": WireGuard only rekeys when data flows, so an idle tunnel's handshake
# ages out even though it is perfectly healthy.
resolve_probe_target() {
    local t cidr base prefix gw
    [ "$(_clean "${WG_PROBE:-true}")" = "true" ] || { info "liveness probe disabled (WG_PROBE=false)"; return; }

    t="$(_clean "${WG_PROBE_TARGET:-}")"
    gw="$(derive_tunnel_gateway)"
    if [ -n "$t" ]; then
        PROBE_TARGET="$t"
    elif [ -n "$gw" ]; then
        PROBE_TARGET="$gw"
    elif [ -n "$WG_FULL_TUNNEL" ]; then
        PROBE_TARGET="1.1.1.1"
    else
        # first non-default AllowedIPs entry: the network's .1 for a subnet, the
        # host itself for a /32
        cidr="$(grep -iE '^[[:space:]]*AllowedIPs[[:space:]]*=' "$WG_CONF" | head -n1 | cut -d= -f2- \
                | tr ',' '\n' | tr -d ' ' \
                | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' | grep -v '^0\.0\.0\.0/0$' | head -n1)"
        if [ -n "$cidr" ]; then
            base="${cidr%/*}"; prefix="${cidr#*/}"
            if [ "$prefix" = "32" ]; then
                PROBE_TARGET="$base"
            else
                PROBE_TARGET="$(printf '%s' "$base" | awk -F. -v OFS=. '{ $4 = 1; print }')"
            fi
        fi
    fi

    if [ -z "$PROBE_TARGET" ]; then
        warn "no probe target could be derived — set WG_PROBE_TARGET to enable auto-recovery"
        return
    fi
    info "liveness probe: ping $PROBE_TARGET via $WG_IFACE every $(_clean "${WG_PROBE_INTERVAL:-30}")s"
}

# A derived target can simply be wrong (a peer that drops ICMP, a gateway that
# is not .1). Rather than bounce the tunnel forever over a bad guess, prove the
# target is reachable once at startup and drop the probe if it is not.
validate_probe_target() {
    local i=0
    [ -z "$PROBE_TARGET" ] && return
    while [ "$i" -lt 6 ]; do
        if ping -c 1 -W 3 -I "$WG_IFACE" "$PROBE_TARGET" >/dev/null 2>&1; then
            info "probe target $PROBE_TARGET is reachable through $WG_IFACE"
            return
        fi
        i=$(( i + 1 ))
        sleep 3
    done
    warn "probe target $PROBE_TARGET is unreachable through $WG_IFACE — disabling auto-recovery"
    warn "  (set WG_PROBE_TARGET to an address that answers ICMP through the tunnel)"
    PROBE_TARGET=""
}

tunnel_healthy() {
    ip link show "$WG_IFACE" >/dev/null 2>&1 || { warn "$WG_IFACE disappeared"; return 1; }
    ping -c 1 -W 3 -I "$WG_IFACE" "$PROBE_TARGET" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# shadowsocks-rust (external entry point)
# ---------------------------------------------------------------------------
start_shadowsocks() {
    local port;   port="$(_clean "${SS_PORT:-8388}")"
    local method; method="$(_clean "${SS_METHOD:-chacha20-ietf-poly1305}")"
    local mode;   mode="$(_clean "${SS_MODE:-tcp_and_udp}")"
    local obfs;   obfs="$(_clean "${SS_OBFS:-http}")"
    local obfs_host; obfs_host="$(_clean "${SS_OBFS_HOST:-}")"
    local password="${SS_PASSWORD:-}"

    [ -z "$password" ] && {
        password="$(pwgen -ns 32 1 2>/dev/null || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
        warn "SS_PASSWORD not set, generated one: $password"
    }

    # Build the ss-server config with jq so it is valid JSON with or without the
    # obfs plugin. simple-obfs's server has no obfs-host flag — obfs-host is a
    # CLIENT setting, so we only pass obfs=<mode> here and log the host clients
    # should use.
    local config=/etc/shadowsocks/config.json
    local base
    base=$(jq -n \
        --argjson port "$port" \
        --arg password "$password" \
        --arg method "$method" \
        --arg mode "$mode" \
        '{server:"0.0.0.0", server_port:$port, password:$password, timeout:300,
          method:$method, mode:$mode, fast_open:false}')
    if [ "$obfs" != "none" ] && [ -n "$obfs" ]; then
        echo "$base" | jq --arg obfs "$obfs" \
            '. + {plugin:"obfs-server", plugin_opts:("obfs=" + $obfs)}' >"$config"
    else
        echo "$base" >"$config"
    fi

    info "shadowsocks config:"
    info "  server_port : $port"
    info "  password    : $password"
    info "  method      : $method"
    info "  mode        : $mode"
    if [ "$obfs" != "none" ] && [ -n "$obfs" ]; then
        info "  obfs        : $obfs  (clients set plugin_opts: obfs=${obfs}${obfs_host:+;obfs-host=$obfs_host})"
    else
        info "  obfs        : disabled"
    fi

    info "starting ss-server..."
    ss-server -c "$config" &
    SS_PID=$!
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
render_wg_config
prepare_conf
probe_wg_mode
start_wireguard
apply_dns
resolve_probe_target
validate_probe_target
start_shadowsocks

# Supervise ss-server and the tunnel. ss-server dying tears the container down
# so docker's restart policy takes over; a dead tunnel is repaired in place.
probe_interval="$(_clean "${WG_PROBE_INTERVAL:-30}")"
probe_failures="$(_clean "${WG_PROBE_FAILURES:-3}")"
handshake_timeout="$(_clean "${WG_HANDSHAKE_TIMEOUT:-180}")"
max_restarts="$(_clean "${WG_MAX_RESTARTS:-5}")"
fails=0
restarts=0
next_probe=0

while true; do
    if ! kill -0 "$SS_PID" 2>/dev/null; then
        warn "ss-server exited"
        break
    fi

    now="$(date +%s)"
    if [ "$now" -ge "$next_probe" ]; then
        next_probe=$(( now + probe_interval ))
        if [ -n "$PROBE_TARGET" ]; then
            if tunnel_healthy; then
                # a restart zeroes `fails`, so check both counters
                { [ "$fails" -gt 0 ] || [ "$restarts" -gt 0 ]; } && info "$WG_IFACE recovered"
                fails=0
                restarts=0
            else
                fails=$(( fails + 1 ))
                warn "$WG_IFACE probe failed ($fails/$probe_failures) — last handshake $(handshake_age)s ago"
                if [ "$fails" -ge "$probe_failures" ]; then
                    restarts=$(( restarts + 1 ))
                    if [ "$restarts" -gt "$max_restarts" ]; then
                        warn "$WG_IFACE did not recover after $max_restarts restarts — exiting for a clean container restart"
                        break
                    fi
                    restart_wireguard || true
                    fails=0
                    next_probe=$(( $(date +%s) + 10 ))
                fi
            fi
        else
            if ! ip link show "$WG_IFACE" >/dev/null 2>&1; then
                warn "$WG_IFACE disappeared"
                break
            fi
            age="$(handshake_age)"
            if [ "$age" -lt 0 ] || [ "$age" -gt "$handshake_timeout" ]; then
                warn "$WG_IFACE has no recent handshake (${age}s) — no probe target, not auto-restarting"
            fi
        fi
    fi
    sleep 5
done

shutdown
exit 1
