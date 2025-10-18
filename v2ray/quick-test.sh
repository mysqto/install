#!/usr/bin/env bash

# Quick test script for rapid testing during development
# Tests on a single distro (Ubuntu 22.04) with both server and client

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="v2ray-quick-test-$$"

function info() { echo -e "${GREEN}[INFO]${NC} $*"; }
function error() { echo -e "${RED}[ERROR]${NC} $*"; }
function warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

function cleanup() {
    if [ -n "$CONTAINER_NAME" ]; then
        info "Cleaning up container..."
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

info "Starting quick test with Ubuntu 22.04..."

# Start container
info "Starting container..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --privileged \
    -v "$SCRIPT_DIR:/v2ray:ro" \
    ubuntu:22.04 \
    /bin/sh -c "while true; do sleep 1000; done" >/dev/null

sleep 2

# Prepare container
info "Preparing container..."
docker exec "$CONTAINER_NAME" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq curl unzip procps >/dev/null 2>&1
" || warn "Some packages failed to install"

info "Note: Docker containers typically don't have systemd"
info "Tests will verify installation but not service functionality"
info "TUN mode tests verify config only (actual TUN interface requires kernel support)"

# Test server installation
info "=========================================="
info "Testing SERVER installation..."
info "=========================================="
docker exec "$CONTAINER_NAME" /bin/bash -c "/v2ray/install --server --port 10086"

# Verify server
info "Verifying server installation..."
docker exec "$CONTAINER_NAME" /bin/bash -c "
    set -e
    test -f /usr/local/bin/v2ray || exit 1
    test -f /usr/local/etc/v2ray/config.json || exit 1
    /usr/local/bin/v2ray version || exit 1
    grep -q '\"port\": 10086' /usr/local/etc/v2ray/config.json || exit 1
    grep -q '\"protocol\": \"vmess\"' /usr/local/etc/v2ray/config.json || exit 1
    # Test config validity
    /usr/local/bin/v2ray test -config /usr/local/etc/v2ray/config.json || exit 1
"
info "✓ Server installation verified"
info "✓ Server config is valid"

# Extract UUID for client test
UUID=$(docker exec "$CONTAINER_NAME" /bin/bash -c "grep -oE '\"id\": *\"[^\"]+\"' /usr/local/etc/v2ray/config.json | head -1 | cut -d'\"' -f4")
info "Server UUID: $UUID"

# Test client installation (with different prefix to avoid conflict)
info ""
info "=========================================="
info "Testing CLIENT installation..."
info "=========================================="
docker exec "$CONTAINER_NAME" /bin/bash -c "/v2ray/install --client --address 1.2.3.4 --port 10086 --uuid $UUID --prefix /opt/v2ray-client"

# Verify client
info "Verifying client installation..."
docker exec "$CONTAINER_NAME" /bin/bash -c "
    set -e
    test -f /opt/v2ray-client/bin/v2ray || exit 1
    test -f /opt/v2ray-client/etc/v2ray/config.json || exit 1
    /opt/v2ray-client/bin/v2ray version || exit 1
    grep -q '\"address\": \"1.2.3.4\"' /opt/v2ray-client/etc/v2ray/config.json || exit 1
    grep -q '\"port\": 1080' /opt/v2ray-client/etc/v2ray/config.json || exit 1
    grep -q '\"protocol\": \"socks\"' /opt/v2ray-client/etc/v2ray/config.json || exit 1
    # Test config validity
    /opt/v2ray-client/bin/v2ray test -config /opt/v2ray-client/etc/v2ray/config.json || exit 1
"
info "✓ Client installation verified"
info "✓ Client config is valid"

# Test custom prefix
info ""
info "=========================================="
info "Testing CUSTOM PREFIX installation..."
info "=========================================="
docker exec "$CONTAINER_NAME" /bin/bash -c "/v2ray/install --server --port 20086 --prefix /custom/path"

docker exec "$CONTAINER_NAME" /bin/bash -c "
    set -e
    test -f /custom/path/bin/v2ray || exit 1
    test -f /custom/path/etc/v2ray/config.json || exit 1
    /custom/path/bin/v2ray version || exit 1
    # Test config validity
    /custom/path/bin/v2ray test -config /custom/path/etc/v2ray/config.json || exit 1
"
info "✓ Custom prefix installation verified"
info "✓ Custom prefix config is valid"

# Test TUN mode client
info ""
info "=========================================="
info "Testing CLIENT with TUN mode..."
info "=========================================="
docker exec "$CONTAINER_NAME" /bin/bash -c "/v2ray/install --client --address 1.2.3.4 --port 10086 --uuid $UUID --prefix /opt/v2ray-tun --tun"

# Verify TUN mode client
info "Verifying TUN mode client installation..."
docker exec "$CONTAINER_NAME" /bin/bash -c "
    set -e
    test -f /opt/v2ray-tun/bin/v2ray || exit 1
    test -f /opt/v2ray-tun/etc/v2ray/config.json || exit 1
    /opt/v2ray-tun/bin/v2ray version || exit 1
    # Check for TUN-specific config
    grep -q '\"protocol\": \"tun\"' /opt/v2ray-tun/etc/v2ray/config.json || exit 1
    grep -q '\"name\": \"v2ray-tun\"' /opt/v2ray-tun/etc/v2ray/config.json || exit 1
    grep -q '\"address\": \"10.0.85.1/24\"' /opt/v2ray-tun/etc/v2ray/config.json || exit 1
    grep -q '\"gateway\": \"10.0.85.1\"' /opt/v2ray-tun/etc/v2ray/config.json || exit 1
    grep -q 'dokodemo-door' /opt/v2ray-tun/etc/v2ray/config.json || exit 1
    # Test config validity
    /opt/v2ray-tun/bin/v2ray test -config /opt/v2ray-tun/etc/v2ray/config.json || exit 1
"
info "✓ TUN mode client installation verified"
info "✓ TUN mode config is valid"
info "✓ TUN interface configuration present"

info ""
info "=========================================="
info "✓ All quick tests passed!"
info "  - Server installation"
info "  - Client installation (proxy mode)"
info "  - Client installation (TUN mode)"
info "  - Custom prefix installation"
info "=========================================="

