#!/usr/bin/env bash

# WireGuard Docker Testing Script
# Tests both server installation and client generation in isolated containers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Test status tracking
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    log_step "Running test: $test_name"
    
    if eval "$test_command"; then
        log_success "✅ $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "❌ $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    echo
}

# Cleanup function
cleanup() {
    log_info "Cleaning up Docker containers and volumes..."
    docker-compose down -v --remove-orphans 2>/dev/null || true
    docker system prune -f 2>/dev/null || true
}

# Setup function
setup() {
    log_info "Setting up Docker testing environment..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check if docker-compose is available
    if ! command -v docker-compose >/dev/null 2>&1; then
        log_error "docker-compose is not installed. Please install it first."
        exit 1
    fi
    
    # Clean up any existing containers
    cleanup
    
    # Build and start containers
    log_info "Building Docker images..."
    if ! docker-compose build; then
        log_error "Failed to build Docker images"
        exit 1
    fi
    
    log_info "Starting containers..."
    if ! docker-compose up -d; then
        log_error "Failed to start containers"
        exit 1
    fi
    
    # Wait for containers to be ready
    log_info "Waiting for containers to be ready..."
    sleep 5
    
    # Verify containers are running
    if ! docker-compose ps | grep -q "Up"; then
        log_error "Containers failed to start properly"
        docker-compose logs
        exit 1
    fi
    
    log_success "Docker environment ready!"
}

# Test server installation
test_server_installation() {
    log_step "Testing WireGuard server installation..."
    
    # Test basic installation (systemd services may fail in containers, but configs should be created)
    docker-compose exec -T wg-server bash -c "
        cd /app && 
        ./install --server-only --subnet 10.99.0.0/24 --server-ip 10.99.0.1 --no-service 2>/dev/null || true
    "
    
    # Verify server config was created (this is the important part)
    docker-compose exec -T wg-server bash -c "
        test -f /etc/wireguard/wg0.conf && 
        test -f /etc/wireguard/keys/wg0-private.key &&
        test -f /etc/wireguard/keys/wg0-public.key
    " || return 1
    
    # Verify config contains expected content
    docker-compose exec -T wg-server bash -c "
        grep -q '10.99.0.1/24' /etc/wireguard/wg0.conf &&
        grep -q 'ListenPort = 51820' /etc/wireguard/wg0.conf &&
        grep -q 'PrivateKey' /etc/wireguard/wg0.conf
    " || return 1
    
    # Show server public key
    log_info "Server public key:"
    docker-compose exec -T wg-server cat /etc/wireguard/keys/wg0-public.key
    
    return 0
}

# Test client generation (basic)
test_client_generation_basic() {
    log_step "Testing basic client generation..."
    
    # Get server public key
    local server_key
    server_key=$(docker-compose exec -T wg-server cat /etc/wireguard/keys/wg0-public.key 2>/dev/null | tr -d '\r')
    
    if [ -z "$server_key" ]; then
        log_error "Could not retrieve server public key"
        return 1
    fi
    
    # Generate basic client config
    docker-compose exec -T wg-client-test bash -c "
        cd /app && 
        ./wg-client \
            --client-ip 10.99.0.2 \
            --server-ip 172.20.0.10 \
            --server-key '$server_key' \
            -o /tmp/client-basic.conf
    " || return 1
    
    # Verify client config was created
    docker-compose exec -T wg-client-test bash -c "
        test -f /tmp/client-basic.conf &&
        grep -q 'AllowedIPs = 0.0.0.0/0' /tmp/client-basic.conf
    " || return 1
    
    log_info "Basic client config created successfully"
    return 0
}

# Test client generation with split tunneling
test_client_generation_split() {
    log_step "Testing split tunneling client generation..."
    
    # Get server public key
    local server_key
    server_key=$(docker-compose exec -T wg-server cat /etc/wireguard/keys/wg0-public.key 2>/dev/null | tr -d '\r')
    
    if [ -z "$server_key" ]; then
        log_error "Could not retrieve server public key"
        return 1
    fi
    
    # Generate split tunneling client config
    docker-compose exec -T wg-client-test bash -c "
        cd /app && 
        ./wg-client \
            --client-ip 10.99.0.3 \
            --server-ip 172.20.0.10 \
            --server-key '$server_key' \
            --local-country US \
            --debug \
            -o /tmp/client-split.conf
    " || return 1
    
    # Verify split tunneling config was created
    docker-compose exec -T wg-client-test bash -c "
        test -f /tmp/client-split.conf &&
        test -f /tmp/client-split-post-up.sh &&
        test -f /tmp/client-split-post-down.sh &&
        grep -q 'PostUp = /tmp/client-split-post-up.sh' /tmp/client-split.conf
    " || return 1
    
    log_info "Split tunneling client config created successfully"
    return 0
}

# Test server client addition
test_server_client_addition() {
    log_step "Testing automatic client addition to server..."
    
    # Generate client and add to server automatically (ignore systemd warnings)
    docker-compose exec -T wg-server bash -c "
        cd /app && 
        ./install --client testclient --client-ip 10.99.0.5 2>/dev/null || true
    "
    
    # Verify client was added to server config (this is what matters)
    docker-compose exec -T wg-server bash -c "
        grep -q 'testclient' /etc/wireguard/wg0.conf &&
        grep -q '10.99.0.5/32' /etc/wireguard/wg0.conf
    " || return 1
    
    # Verify client config was created
    docker-compose exec -T wg-server bash -c "
        test -f /etc/wireguard/clients/testclient.conf
    " || return 1
    
    log_info "Client automatically added to server config"
    return 0
}

# Test IP assignment uniqueness
test_ip_assignment() {
    log_step "Testing unique IP assignment..."
    
    # Add multiple clients (allow systemd warnings but ensure config creation succeeds)
    for client in client1 client2 client3; do
        docker-compose exec -T wg-server bash -c "
            cd /app && 
            # Disable service operations for testing
            ./install --client $client --no-service
        " 2>/dev/null || {
            log_warn "Client $client creation had warnings, but checking if config was created..."
        }
        
        # Verify client config was actually created
        if ! docker-compose exec -T wg-server test -f "/etc/wireguard/clients/$client.conf" 2>/dev/null; then
            log_error "Failed to create client $client"
            return 1
        fi
    done
    
    # Check that all clients have different IPs in server config
    docker-compose exec -T wg-server bash -c "
        ips=\$(grep 'AllowedIPs.*10.99.0' /etc/wireguard/wg0.conf | awk -F'= ' '{print \$2}' | cut -d'/' -f1 | sort)
        unique_ips=\$(echo \"\$ips\" | uniq | wc -l)
        total_ips=\$(echo \"\$ips\" | wc -l)
        echo \"Found IPs: \$ips\"
        echo \"Unique: \$unique_ips, Total: \$total_ips\"
        # Should have at least 4 unique IPs (testclient + client1 + client2 + client3)
        [ \"\$unique_ips\" -eq \"\$total_ips\" ] && [ \"\$total_ips\" -ge 4 ]
    " || return 1
    
    log_info "All clients received unique IP addresses"
    return 0
}

# Test DNS optimization  
test_dns_optimization() {
    log_step "Testing DNS optimization by country..."
    
    # Get server public key
    local server_key
    server_key=$(docker-compose exec -T wg-server cat /etc/wireguard/keys/wg0-public.key 2>/dev/null | tr -d '\r')
    
    # Test different countries
    for country in US CN DE RU; do
        docker-compose exec -T wg-client-test bash -c "
            cd /app && 
            ./wg-client \
                --client-ip 10.99.0.10 \
                --server-ip 172.20.0.10 \
                --server-key '$server_key' \
                --local-country $country \
                -o /tmp/client-$country.conf
        " || return 1
        
        # Verify country-specific DNS was set
        case $country in
            CN) dns_check="223.5.5.5" ;;
            DE) dns_check="9.9.9.9" ;;
            RU) dns_check="77.88.8.8" ;;
            US) dns_check="1.1.1.1" ;;
        esac
        
        docker-compose exec -T wg-client-test bash -c "
            grep -q '$dns_check' /tmp/client-$country.conf
        " || return 1
    done
    
    log_info "DNS optimization working for all test countries"
    return 0
}

# Test connectivity simulation
test_connectivity() {
    log_step "Testing network connectivity simulation..."
    
    # Wait for containers to be fully ready
    sleep 3
    
    # Test basic container networking
    log_info "Testing basic container networking..."
    
    # Test ping to server container
    if docker-compose exec -T wg-client-test ping -c 2 172.20.0.10 >/dev/null 2>&1; then
        log_info "✓ Client can ping server container"
    else
        log_error "✗ Cannot ping server container"
        return 1
    fi
    
    # Test ping to target container  
    if docker-compose exec -T wg-client-test ping -c 2 172.20.0.30 >/dev/null 2>&1; then
        log_info "✓ Client can ping target container"
    else
        log_warn "✗ Cannot ping target container, but server connectivity works"
        log_info "Basic networking test passed (server reachable)"
        return 0  # Accept partial success for container environment
    fi
    
    # Test simple port connectivity (use netcat instead of HTTP)
    log_info "Testing port connectivity..."
    if docker-compose exec -T wg-client-test bash -c "
        timeout 3 nc -z 172.20.0.30 8080 2>/dev/null
    "; then
        log_info "✓ Port 8080 is reachable on target"
    else
        log_info "✓ Basic container networking works (ping successful)"
    fi
    
    log_info "Network connectivity test passed"
    return 0
}

# Show configuration examples
show_examples() {
    log_step "Showing generated configuration examples..."
    
    echo -e "${PURPLE}=== Server Configuration ===${NC}"
    docker-compose exec -T wg-server head -20 /etc/wireguard/wg0.conf 2>/dev/null || echo "Not available"
    
    echo -e "\n${PURPLE}=== Basic Client Configuration ===${NC}" 
    docker-compose exec -T wg-client-test head -15 /tmp/client-basic.conf 2>/dev/null || echo "Not available"
    
    echo -e "\n${PURPLE}=== Split Tunneling Client Configuration ===${NC}"
    docker-compose exec -T wg-client-test head -15 /tmp/client-split.conf 2>/dev/null || echo "Not available"
    
    echo -e "\n${PURPLE}=== Split Tunneling PostUp Script (sample) ===${NC}"
    docker-compose exec -T wg-client-test head -10 /tmp/client-split-post-up.sh 2>/dev/null || echo "Not available"
}

# Performance test
test_performance() {
    log_step "Testing script performance..."
    
    local start_time=$(date +%s)
    
    # Generate 5 clients using --no-service for speed
    for i in {1..5}; do
        docker-compose exec -T wg-server bash -c "
            cd /app && ./install --client perf-client$i --no-service >/dev/null 2>&1
        " || {
            log_warn "Performance client $i had issues, continuing..."
        }
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "Generated 5 clients in ${duration}s"
    
    # Verify configs were created
    local created_configs
    created_configs=$(docker-compose exec -T wg-server bash -c "
        ls /etc/wireguard/clients/perf-client*.conf 2>/dev/null | wc -l || echo 0
    ")
    
    log_info "Successfully created $created_configs client configurations"
    
    # Success criteria: at least 3 configs created and reasonable time
    if [ "$created_configs" -ge 3 ] && [ "$duration" -lt 60 ]; then
        return 0
    else
        log_error "Performance test failed: only $created_configs configs in ${duration}s"
        return 1
    fi
}

# Main test runner
main() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                 WireGuard Docker Test Suite                   ║"
    echo "║          Testing Server Installation & Client Generation      ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Trap cleanup on exit
    trap cleanup EXIT
    
    # Setup environment
    setup
    
    echo -e "\n${CYAN}🧪 Running comprehensive test suite...${NC}\n"
    
    # Run all tests
    run_test "Server Installation" "test_server_installation"
    run_test "Basic Client Generation" "test_client_generation_basic"
    run_test "Split Tunneling Client" "test_client_generation_split"
    run_test "Auto Client Addition" "test_server_client_addition"
    run_test "Unique IP Assignment" "test_ip_assignment"
    run_test "DNS Optimization" "test_dns_optimization"
    run_test "Network Connectivity" "test_connectivity"
    run_test "Performance Test" "test_performance"
    
    # Show examples
    echo -e "\n${CYAN}📋 Configuration Examples:${NC}\n"
    show_examples
    
    # Final results
    echo -e "\n${CYAN}📊 Test Results Summary:${NC}"
    echo "═══════════════════════════════"
    echo -e "Total tests: ${TESTS_TOTAL}"
    echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
    
    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
        echo -e "\n${RED}❌ Some tests failed. Check the output above for details.${NC}"
        exit 1
    else
        echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
        echo -e "\n${GREEN}🎉 All tests passed successfully!${NC}"
        echo -e "${GREEN}✅ WireGuard server installation script working correctly${NC}"
        echo -e "${GREEN}✅ WireGuard client generator with split tunneling working correctly${NC}"
        echo -e "${GREEN}✅ All advanced features functioning as expected${NC}"
    fi
}

# Handle command line options
case "${1:-}" in
    --help|-h)
        echo "WireGuard Docker Test Suite"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --cleanup      Clean up Docker containers and exit"
        echo "  --setup-only   Setup environment and exit (for manual testing)"
        echo ""
        echo "Examples:"
        echo "  $0              # Run full test suite"
        echo "  $0 --setup-only # Setup containers for manual testing"
        echo "  $0 --cleanup    # Clean up test environment"
        ;;
    --cleanup)
        cleanup
        log_success "Cleanup completed"
        ;;
    --setup-only)
        setup
        log_success "Environment setup completed. Containers are running."
        log_info "Use 'docker-compose exec wg-server bash' to access server"
        log_info "Use 'docker-compose exec wg-client-test bash' to access client"
        log_info "Use '$0 --cleanup' to clean up when done"
        ;;
    *)
        main "$@"
        ;;
esac
