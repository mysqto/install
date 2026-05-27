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

exec sing-box run -c "$SB_CONFIG"
