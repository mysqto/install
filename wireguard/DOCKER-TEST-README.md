# WireGuard Docker Testing Environment

A comprehensive Docker-based testing environment for the WireGuard server installation script and client generator with GeoIP routing.

## Quick Start

```bash
# Run the full test suite
./test-docker.sh

# Setup environment for manual testing
./test-docker.sh --setup-only

# Clean up when done
./test-docker.sh --cleanup
```

## What Gets Tested

### ✅ Server Installation Tests
- **WireGuard installation** in clean Ubuntu container
- **Server configuration generation** with custom subnets
- **Key generation and management** (private/public keypairs)
- **Network configuration** (IP forwarding, iptables rules)
- **Service configuration** (systemd integration)

### ✅ Client Generation Tests  
- **Basic client configs** (full tunnel mode)
- **Split tunneling configs** with GeoIP routing
- **Automatic key generation** when not provided
- **DNS optimization** by country (US, CN, DE, RU)
- **Multiple client support** with unique IP assignment
- **QR code generation** capability

### ✅ Integration Tests
- **Client auto-addition** to server configuration  
- **IP conflict prevention** (unique IP assignment)
- **Network connectivity** between containers
- **Performance testing** (multiple client generation)
- **Configuration validation** (syntax and completeness)

### ✅ Advanced Features
- **GeoIP split tunneling** - Routes local traffic direct, international via VPN
- **Country-specific DNS** - Optimized DNS servers per location  
- **Routing script generation** - PostUp/PostDown scripts for split tunneling
- **Multiple subnet support** - Automatic subnet conflict detection

## Architecture

### Container Setup
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   wg-server     │    │ wg-client-test  │    │  test-target    │
│  172.20.0.10    │◄──►│   172.20.0.20   │◄──►│  172.20.0.30    │
│                 │    │                 │    │                 │
│ Tests server    │    │ Tests client    │    │ HTTP test       │
│ installation    │    │ generation      │    │ server          │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       Test Network
                      172.20.0.0/24
```

### Network Simulation
- **Server Container**: Tests WireGuard server setup and client management
- **Client Container**: Tests client config generation and split tunneling
- **Target Container**: Simulates external services for connectivity testing
- **Isolated Network**: Prevents interference with host networking

## Test Categories

### 🔧 Installation Tests
- Package installation across distributions
- Kernel module loading and configuration  
- System service setup and enablement
- Network interface configuration

### 🌐 Networking Tests
- IP forwarding configuration
- iptables rule generation
- Subnet overlap detection
- Default route detection

### 🔑 Security Tests  
- Private key generation and protection
- Public key extraction and sharing
- Configuration file permissions
- Key storage security

### 🌍 GeoIP Tests
- Country IP range download
- Split tunneling rule generation
- DNS server optimization  
- Routing script creation

### 📱 Client Tests
- Configuration file generation
- QR code creation (if tools available)
- Multiple client scenarios
- Custom parameter handling

## Manual Testing

For interactive testing and debugging:

```bash
# Setup containers without running tests
./test-docker.sh --setup-only

# Access server container  
docker-compose exec wg-server bash

# Access client container
docker-compose exec wg-client-test bash

# View logs
docker-compose logs wg-server
docker-compose logs wg-client-test

# Clean up when done
./test-docker.sh --cleanup
```

## Example Test Output

```
╔═══════════════════════════════════════════════════════════════╗
║                 WireGuard Docker Test Suite                   ║
║          Testing Server Installation & Client Generation      ║  
╚═══════════════════════════════════════════════════════════════╝

🧪 Running comprehensive test suite...

[STEP] Running test: Server Installation
[SUCCESS] ✅ Server Installation

[STEP] Running test: Basic Client Generation  
[SUCCESS] ✅ Basic Client Generation

[STEP] Running test: Split Tunneling Client
[SUCCESS] ✅ Split Tunneling Client

[STEP] Running test: Auto Client Addition
[SUCCESS] ✅ Auto Client Addition

[STEP] Running test: Unique IP Assignment
[SUCCESS] ✅ Unique IP Assignment

[STEP] Running test: DNS Optimization
[SUCCESS] ✅ DNS Optimization

[STEP] Running test: Network Connectivity
[SUCCESS] ✅ Network Connectivity

[STEP] Running test: Performance Test
[SUCCESS] ✅ Performance Test

📊 Test Results Summary:
═══════════════════════════════
Total tests: 8
Passed: 8
Failed: 0

🎉 All tests passed successfully!
✅ WireGuard server installation script working correctly
✅ WireGuard client generator with split tunneling working correctly  
✅ All advanced features functioning as expected
```

## Requirements

- **Docker** - Container runtime
- **Docker Compose** - Multi-container orchestration  
- **Bash** - Script execution
- **Linux kernel** with WireGuard support (for full functionality)

## Troubleshooting

### Common Issues

1. **Docker not running**
   ```bash
   sudo systemctl start docker
   ```

2. **Permission denied**
   ```bash
   sudo usermod -aG docker $USER
   # Log out and back in
   ```

3. **Port conflicts**
   ```bash
   ./test-docker.sh --cleanup
   docker system prune -f
   ```

4. **WireGuard module issues**
   - Normal in some container environments
   - Tests focus on script logic rather than kernel functionality

### Debug Mode

Enable verbose logging:
```bash
DEBUG=1 ./test-docker.sh
```

View detailed container logs:
```bash
docker-compose logs --follow wg-server
docker-compose logs --follow wg-client-test
```

## Files Created

After running tests, the following structure is created:

```
wireguard/
├── Dockerfile              # Container image definition
├── docker-compose.yml      # Multi-container setup
├── test-docker.sh         # Main test script
├── DOCKER-TEST-README.md  # This documentation
├── install                # Server installation script  
├── wg-client             # Client generator script
└── CLIENT-README.md      # Client documentation
```

## Use Cases

### Development Testing
- Validate script changes before deployment
- Test cross-platform compatibility  
- Verify security configurations

### CI/CD Integration
- Automated testing in build pipelines
- Regression testing for updates
- Quality assurance validation

### Educational Purposes  
- Demonstrate WireGuard configuration
- Show split tunneling concepts
- Illustrate container networking

### Production Validation
- Test configurations before deployment
- Validate client generation workflows
- Verify GeoIP routing functionality

