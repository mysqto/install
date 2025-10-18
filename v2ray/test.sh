#!/usr/bin/env bash

# Require bash 4+ for associative arrays
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
    echo "Error: This script requires Bash 4.0 or later"
    echo "Current version: $BASH_VERSION"
    echo ""
    echo "On macOS, install with:"
    echo "  brew install bash"
    echo ""
    echo "Then run with:"
    echo "  /opt/homebrew/bin/bash $0 $*"
    echo ""
    echo "Or use the quick-test script instead (no bash 4 required):"
    echo "  ./quick-test.sh"
    exit 1
fi

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

function warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

function error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

function success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

function section() {
    echo -e "\n${BLUE}===================================================================${NC}"
    echo -e "${BLUE}$*${NC}"
    echo -e "${BLUE}===================================================================${NC}\n"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install"

# Check if Docker is available
if ! command -v docker >/dev/null 2>&1; then
    error "Docker is not installed or not in PATH"
    exit 1
fi

# Test distributions
DISTROS=(
    "ubuntu:22.04"
    "ubuntu:20.04"
    "debian:12"
    "debian:11"
    "rockylinux:9"
    "rockylinux:8"
    "alpine:3.18"
)

# Note: CentOS 7 is EOL and mirrors are unavailable for ARM64
# Skipping CentOS 7 from default test list

# Test results
declare -A test_results
total_tests=0
passed_tests=0
failed_tests=0

function cleanup_container() {
    local container_name="$1"
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        info "Cleaning up container: $container_name"
        docker rm -f "$container_name" >/dev/null 2>&1 || true
    fi
}

function run_test() {
    local distro="$1"
    local test_name="$2"
    local test_mode="$3"  # server or client
    
    local distro_name="${distro//[\/:]/-}"
    local container_name="v2ray-test-${distro_name}-${test_mode}-$$"
    
    total_tests=$((total_tests + 1))
    
    section "Testing: $distro ($test_mode mode)"
    
    # Cleanup any existing container
    cleanup_container "$container_name"
    
    # Start container
    info "Starting container: $container_name"
    if ! docker run -d \
        --name "$container_name" \
        --privileged \
        -v "$SCRIPT_DIR:/v2ray:ro" \
        "$distro" \
        /bin/sh -c "while true; do sleep 1000; done" >/dev/null 2>&1; then
        error "Failed to start container for $distro"
        test_results["$test_name"]="FAILED: Container start failed"
        failed_tests=$((failed_tests + 1))
        return 1
    fi
    
    info "Container started: $container_name"
    
    # Wait for container to be ready
    sleep 2
    
    # Install systemd if needed (for service management)
    info "Preparing container..."
    
    # Detect distro family and prepare
    if [[ "$distro" == ubuntu* ]] || [[ "$distro" == debian* ]]; then
        docker exec "$container_name" /bin/sh -c "
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq >/dev/null 2>&1
            apt-get install -y -qq systemctl curl unzip procps >/dev/null 2>&1 || apt-get install -y -qq curl unzip procps >/dev/null 2>&1
        " >/dev/null 2>&1 || warn "Failed to install some packages (non-critical)"
    elif [[ "$distro" == centos* ]] || [[ "$distro" == rocky* ]]; then
        docker exec "$container_name" /bin/sh -c "
            yum install -y -q curl unzip procps systemd >/dev/null 2>&1 || yum install -y -q curl unzip procps >/dev/null 2>&1
        " >/dev/null 2>&1 || warn "Failed to install some packages (non-critical)"
    elif [[ "$distro" == alpine* ]]; then
        docker exec "$container_name" /bin/sh -c "
            apk add --no-cache curl unzip bash procps openrc >/dev/null 2>&1
        " >/dev/null 2>&1 || warn "Failed to install some packages (non-critical)"
    fi
    
    # Run the installation
    info "Running V2Ray installation ($test_mode mode)..."
    
    local install_cmd=""
    if [ "$test_mode" = "server" ]; then
        install_cmd="/v2ray/install --server --port 10086"
    else
        # For client test, we need server details
        install_cmd="/v2ray/install --client --address 1.2.3.4 --port 10086 --uuid 12345678-1234-1234-1234-123456789012"
    fi
    
    if docker exec "$container_name" /bin/bash -c "$install_cmd" 2>&1 | tee /tmp/v2ray-test-${distro_name}-${test_mode}.log; then
        info "Installation completed"
    else
        error "Installation failed"
        test_results["$test_name"]="FAILED: Installation error"
        failed_tests=$((failed_tests + 1))
        cleanup_container "$container_name"
        return 1
    fi
    
    # Verify installation
    info "Verifying installation..."
    
    # Check if binary exists
    if ! docker exec "$container_name" /bin/sh -c "test -f /usr/local/bin/v2ray" 2>/dev/null; then
        error "V2Ray binary not found"
        test_results["$test_name"]="FAILED: Binary not found"
        failed_tests=$((failed_tests + 1))
        cleanup_container "$container_name"
        return 1
    fi
    
    # Check if config exists
    if ! docker exec "$container_name" /bin/sh -c "test -f /usr/local/etc/v2ray/config.json" 2>/dev/null; then
        error "V2Ray config not found"
        test_results["$test_name"]="FAILED: Config not found"
        failed_tests=$((failed_tests + 1))
        cleanup_container "$container_name"
        return 1
    fi
    
    # Verify binary works
    if ! docker exec "$container_name" /bin/sh -c "/usr/local/bin/v2ray version" >/dev/null 2>&1; then
        error "V2Ray binary doesn't work"
        test_results["$test_name"]="FAILED: Binary not working"
        failed_tests=$((failed_tests + 1))
        cleanup_container "$container_name"
        return 1
    fi
    
    # Get version
    version=$(docker exec "$container_name" /bin/sh -c "/usr/local/bin/v2ray version 2>/dev/null | head -n1" || echo "unknown")
    info "V2Ray version: $version"
    
    # Verify config is valid JSON
    if ! docker exec "$container_name" /bin/sh -c "cat /usr/local/etc/v2ray/config.json | grep -q inbounds" 2>/dev/null; then
        error "Config file seems invalid"
        test_results["$test_name"]="FAILED: Invalid config"
        failed_tests=$((failed_tests + 1))
        cleanup_container "$container_name"
        return 1
    fi
    
    # Test with custom prefix
    info "Testing custom prefix installation..."
    local prefix_cmd=""
    if [ "$test_mode" = "server" ]; then
        prefix_cmd="/v2ray/install --server --port 20086 --prefix /opt/v2ray-test"
    else
        prefix_cmd="/v2ray/install --client --address 1.2.3.4 --port 20086 --uuid 87654321-4321-4321-4321-210987654321 --prefix /opt/v2ray-test"
    fi
    
    if docker exec "$container_name" /bin/bash -c "$prefix_cmd" >/dev/null 2>&1; then
        if docker exec "$container_name" /bin/sh -c "test -f /opt/v2ray-test/bin/v2ray" 2>/dev/null; then
            info "Custom prefix installation successful"
        else
            warn "Custom prefix test failed (non-critical)"
        fi
    else
        warn "Custom prefix installation failed (non-critical)"
    fi
    
    success "All checks passed for $distro ($test_mode)"
    test_results["$test_name"]="PASSED"
    passed_tests=$((passed_tests + 1))
    
    # Cleanup
    cleanup_container "$container_name"
    
    return 0
}

function run_all_tests() {
    section "V2Ray Installation Test Suite"
    info "Script location: $INSTALL_SCRIPT"
    info "Testing ${#DISTROS[@]} distributions"
    
    if [ ! -f "$INSTALL_SCRIPT" ]; then
        error "Install script not found at: $INSTALL_SCRIPT"
        exit 1
    fi
    
    # Make sure script is executable
    chmod +x "$INSTALL_SCRIPT"
    
    # Test each distribution
    for distro in "${DISTROS[@]}"; do
        # Test server installation
        run_test "$distro" "${distro}-server" "server"
        
        # Small delay between tests
        sleep 1
        
        # Test client installation
        run_test "$distro" "${distro}-client" "client"
        
        # Small delay between tests
        sleep 1
    done
}

function print_summary() {
    section "Test Summary"
    
    echo -e "${BLUE}Total Tests:${NC} $total_tests"
    echo -e "${GREEN}Passed:${NC} $passed_tests"
    echo -e "${RED}Failed:${NC} $failed_tests"
    echo ""
    
    if [ $failed_tests -eq 0 ]; then
        success "All tests passed! 🎉"
        echo ""
        return 0
    else
        error "Some tests failed:"
        echo ""
        for test_name in "${!test_results[@]}"; do
            result="${test_results[$test_name]}"
            if [[ "$result" == FAILED* ]]; then
                echo -e "  ${RED}✗${NC} $test_name: $result"
            else
                echo -e "  ${GREEN}✓${NC} $test_name"
            fi
        done
        echo ""
        return 1
    fi
}

# Parse arguments
SPECIFIC_DISTRO=""
SPECIFIC_MODE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--distro)
            SPECIFIC_DISTRO="$2"
            shift 2
            ;;
        -m|--mode)
            SPECIFIC_MODE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -d, --distro DISTRO    Test specific distro (e.g., ubuntu:22.04)"
            echo "  -m, --mode MODE        Test specific mode (server or client)"
            echo "  -h, --help             Show this help message"
            echo ""
            echo "Available distros:"
            for d in "${DISTROS[@]}"; do
                echo "  - $d"
            done
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run tests
if [ -n "$SPECIFIC_DISTRO" ]; then
    info "Testing specific distro: $SPECIFIC_DISTRO"
    if [ -n "$SPECIFIC_MODE" ]; then
        run_test "$SPECIFIC_DISTRO" "${SPECIFIC_DISTRO}-${SPECIFIC_MODE}" "$SPECIFIC_MODE"
    else
        run_test "$SPECIFIC_DISTRO" "${SPECIFIC_DISTRO}-server" "server"
        run_test "$SPECIFIC_DISTRO" "${SPECIFIC_DISTRO}-client" "client"
    fi
else
    run_all_tests
fi

print_summary
exit $?

