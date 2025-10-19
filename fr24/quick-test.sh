#!/usr/bin/env bash

# Quick test script for FR24 installation
# Tests on a single distro (Ubuntu 22.04)

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="fr24-quick-test-$$"

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
    -v "$SCRIPT_DIR:/fr24:ro" \
    ubuntu:22.04 \
    /bin/sh -c "while true; do sleep 1000; done" >/dev/null

sleep 2

# Prepare container
info "Preparing container..."
docker exec "$CONTAINER_NAME" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq curl tar procps >/dev/null 2>&1
" || warn "Some packages failed to install"

info "Note: Docker containers typically don't have systemd"
info "Tests will verify installation but not service functionality"

# Test basic installation
info "=========================================="
info "Testing FR24 installation..."
info "=========================================="
docker exec "$CONTAINER_NAME" /bin/bash -c "/fr24/install --key TEST_KEY_12345"

# Verify installation
info "Verifying FR24 installation..."
docker exec "$CONTAINER_NAME" /bin/bash -c "
    set -e
    test -f /usr/local/bin/fr24feed || exit 1
    test -f /usr/local/etc/fr24feed/fr24feed.ini || exit 1
    /usr/local/bin/fr24feed --version || exit 1
    grep -q 'fr24key=\"TEST_KEY_12345\"' /usr/local/etc/fr24feed/fr24feed.ini || exit 1
    grep -q 'receiver=\"dvbt\"' /usr/local/etc/fr24feed/fr24feed.ini || exit 1
"
info "✓ Basic installation verified"
info "✓ Config file valid"

# Test with location
info ""
info "=========================================="
info "Testing with location data..."
info "=========================================="
docker exec "$CONTAINER_NAME" /bin/bash -c "/fr24/install --key TEST_KEY_67890 --lat 51.5074 --lon -0.1278 --alt 50 --prefix /opt/fr24"

# Verify location config
info "Verifying location configuration..."
docker exec "$CONTAINER_NAME" /bin/bash -c "
    set -e
    test -f /opt/fr24/bin/fr24feed || exit 1
    test -f /opt/fr24/etc/fr24feed/fr24feed.ini || exit 1
    grep -q 'fr24key=\"TEST_KEY_67890\"' /opt/fr24/etc/fr24feed/fr24feed.ini || exit 1
    grep -q 'latitude=\"51.5074\"' /opt/fr24/etc/fr24feed/fr24feed.ini || exit 1
    grep -q 'longitude=\"-0.1278\"' /opt/fr24/etc/fr24feed/fr24feed.ini || exit 1
    grep -q 'altitude=\"50\"' /opt/fr24/etc/fr24feed/fr24feed.ini || exit 1
"
info "✓ Location configuration verified"
info "✓ Custom prefix installation verified"

# Test different receiver type
info ""
info "=========================================="
info "Testing with Beast receiver..."
info "=========================================="
docker exec "$CONTAINER_NAME" /bin/bash -c "/fr24/install --key TEST_BEAST --receiver beast --prefix /opt/fr24-beast"

docker exec "$CONTAINER_NAME" /bin/bash -c "
    set -e
    test -f /opt/fr24-beast/bin/fr24feed || exit 1
    grep -q 'receiver=\"beast\"' /opt/fr24-beast/etc/fr24feed/fr24feed.ini || exit 1
"
info "✓ Beast receiver configuration verified"

info ""
info "=========================================="
info "✓ All quick tests passed!"
info "  - Basic installation"
info "  - Location configuration"
info "  - Custom prefix"
info "  - Receiver types"
info "=========================================="

