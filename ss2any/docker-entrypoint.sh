#!/bin/bash
set -euo pipefail

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
info()  { echo -e "\033[32m[$(timestamp)] INFO: $*\033[0m"; }
warn()  { echo -e "\033[33m[$(timestamp)] WARN: $*\033[0m" >&2; }
error() { echo -e "\033[31m[$(timestamp)] ERROR: $*\033[0m" >&2; exit 1; }

CONFIG_DIR="/config"
SB_CONFIG="${CONFIG_DIR}/sing-box.json"
SS2ANY_CONFIG="${SS2ANY_CONFIG:-/config/ss2any.yaml}"
mkdir -p "$CONFIG_DIR"

# Single-link fallback: generate-config.py also accepts no file and PROXY_LINK env.
# Auto-generate SS_PASSWORD only in single-link mode (multi-inbound configs must
# specify their own passwords).
if [ ! -f "$SS2ANY_CONFIG" ]; then
    if [ -z "${PROXY_LINK:-}" ]; then
        error "no $SS2ANY_CONFIG and no PROXY_LINK env var"
    fi
    if [ -z "${SS_PASSWORD:-}" ]; then
        SS_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
        warn "SS_PASSWORD not set, generated one: $SS_PASSWORD"
        export SS_PASSWORD
    fi
    # When obfs is requested, sing-box binds to a loopback port and an external
    # obfs-server owns the public port. Pick a default internal port if unset.
    if [ -n "${SS_OBFS_HOST:-}" ] && [ -z "${SS_OBFS_INTERNAL_PORT:-}" ]; then
        SS_OBFS_INTERNAL_PORT=18388
        export SS_OBFS_INTERNAL_PORT
        info "SS_OBFS_INTERNAL_PORT not set, defaulting to $SS_OBFS_INTERNAL_PORT"
    fi
fi

info "Generating sing-box config..."
config_arg=()
[ -f "$SS2ANY_CONFIG" ] && config_arg=("$SS2ANY_CONFIG")
if ! /usr/local/bin/generate-config.py generate "${config_arg[@]}" >"$SB_CONFIG.tmp"; then
    rm -f "$SB_CONFIG.tmp"
    error "Failed to generate sing-box config"
fi
mv "$SB_CONFIG.tmp" "$SB_CONFIG"

if ! sing-box check -c "$SB_CONFIG"; then
    error "sing-box config validation failed; see $SB_CONFIG"
fi

OBFS_PID=""
SB_PID=""

shutdown() {
    [ -n "$SB_PID" ]   && kill -TERM "$SB_PID"   2>/dev/null || true
    [ -n "$OBFS_PID" ] && kill -TERM "$OBFS_PID" 2>/dev/null || true
}
trap shutdown TERM INT HUP

# Single-link obfs: start obfs-server in front of sing-box's loopback inbound.
# For YAML mode we don't auto-spawn obfs-server (each inbound needs its own
# args and there's no clean way to discover them from the env); the YAML
# author owns the obfs front-end in that case.
if [ ! -f "$SS2ANY_CONFIG" ] && [ -n "${SS_OBFS_HOST:-}" ]; then
    if ! command -v obfs-server >/dev/null 2>&1; then
        error "SS_OBFS_HOST=$SS_OBFS_HOST but obfs-server not in PATH"
    fi
    obfs_mode="${SS_OBFS_MODE:-http}"
    obfs_port="${SS_PORT:-8388}"
    # NOTE: simple-obfs's server has no --obfs-host flag — the masquerade
    # Host header is a CLIENT-side setting. SS_OBFS_HOST is the value your
    # SS+obfs clients should configure (it's logged for that reason).
    #
    # simple-obfs does not clear IPV6_V6ONLY, so "-s ::" is IPv6-only on
    # most kernels. Default to 0.0.0.0 so IPv4 clients work; users wanting
    # IPv6 can set SS_OBFS_LISTEN=::.
    obfs_listen="${SS_OBFS_LISTEN:-0.0.0.0}"
    info "Starting obfs-server ${obfs_listen}:${obfs_port} (mode=${obfs_mode}) -> 127.0.0.1:${SS_OBFS_INTERNAL_PORT}"
    info "Tell your SS clients to set plugin_opts: obfs=${obfs_mode};obfs-host=${SS_OBFS_HOST}"
    obfs-server -s "$obfs_listen" -p "$obfs_port" \
                -r "127.0.0.1:${SS_OBFS_INTERNAL_PORT}" \
                --obfs "$obfs_mode" \
                -t 300 &
    OBFS_PID=$!
fi

sing-box run -c "$SB_CONFIG" &
SB_PID=$!

wait "$SB_PID"
sb_exit=$?
shutdown
wait 2>/dev/null || true
exit "$sb_exit"
