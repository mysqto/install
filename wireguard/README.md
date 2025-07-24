# WireGuard Installation Script

A simple script to install and configure WireGuard VPN on Linux servers with automatic key generation and cross-distribution support.

## Features

- **Multi-distribution support**: Ubuntu, Debian, CentOS, RHEL, Fedora, Rocky Linux, AlmaLinux, Arch, openSUSE, Alpine
- **Multi-architecture support**: x86_64 (amd64), ARM64 (aarch64), i386
- **Automatic key generation**: Server and client keys generated automatically
- **Network forwarding setup**: Automatic IP forwarding and iptables rules
- **Dynamic interface detection**: Automatically detects default network interface
- **Client configuration generation**: Easy client config generation with QR codes
- **Colorful logging**: Clear visual feedback during installation

## Command Line Options

- `-h, --help`: Show help message
- `-i, --interface NAME`: Specify interface name (default: wg0)
- `-c, --client NAME`: Generate client configuration (creates server config if needed)
- `--server-only`: Create server configuration only (skip WireGuard installation)
- `--server-ip IP`: Server VPN IP address (default: 10.0.0.1)
- `--client-ip IP`: Client VPN IP address (default: 10.0.0.2)
- `--subnet CIDR`: VPN subnet (default: 10.0.0.0/24)
- `--port PORT`: Listen port (default: 51820)
- `--public-ip IP`: Server's public IP (auto-detected if not specified)
- `--dns SERVERS`: DNS servers for clients (auto-selected by location if not specified)
- `--no-template`: Skip configuration template generation
- `--no-service`: Skip service enablement

## Usage Examples

### Basic Installation

```bash
# Basic installation with default settings
./install

# Installation with custom interface name
./install -i wg1

# Installation without service auto-start
./install --no-service
```

### Server Configuration Only

```bash
# Create server configuration without installing WireGuard
./install --server-only

# Create server configuration with custom settings
./install --server-only --interface wg1 --server-ip 192.168.100.1 --subnet 192.168.100.0/24 --port 51821
```

### Client Configuration

```bash
# Generate client configuration (creates server config if needed)
./install --client alice

# Generate client with custom settings
./install --client bob --client-ip 10.0.0.10 --dns "8.8.8.8,1.1.1.1"
```

### Advanced Installation

```bash
# Custom IP range
./install --server-ip 192.168.100.1 --subnet 192.168.100.0/24

# Custom port and DNS
./install --port 51821 --dns "8.8.8.8,1.1.1.1"

# Specify public IP (useful for NAT environments)
./install --public-ip 203.0.113.10
```

## What the Script Does

1. **Detects your Linux distribution and architecture**
2. **Installs WireGuard** using the appropriate package manager
3. **Enables IP forwarding** in kernel and makes it permanent
4. **Creates post-up/post-down scripts** with dynamic interface detection
5. **Generates server keys** automatically
6. **Creates server configuration** with generated keys
7. **Enables systemd service** for auto-start
8. **Auto-restarts service** when adding new clients or server configurations

## File Locations

- **Server config**: `/etc/wireguard/wg0.conf`
- **Server keys**: `/etc/wireguard/keys/`
- **Client configs**: `/etc/wireguard/clients/`
- **Post scripts**: `/etc/wireguard/post-up.sh` and `/etc/wireguard/post-down.sh`

## Example Configuration

### Server Config (`/etc/wireguard/wg0.conf`)

```ini
[Interface]
PrivateKey = [AUTO-GENERATED]
Address = 192.168.100.1/24
ListenPort = 51820
PostUp = /etc/wireguard/post-up.sh
PostDown = /etc/wireguard/post-down.sh

[Peer]
PublicKey = [CLIENT_PUBLIC_KEY]
AllowedIPs = 192.168.100.2/32
```

### Client Config

```ini
[Interface]
PrivateKey = [AUTO-GENERATED]
Address = 192.168.100.2/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = [SERVER_PUBLIC_KEY]
Endpoint = 203.0.113.10:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

## Common IP Range Examples

### Home Network (192.168.x.x)

```bash
sudo ./install --subnet 192.168.100.0/24 --server-ip 192.168.100.1
```

### Enterprise Network (172.16.x.x)

```bash
sudo ./install --subnet 172.16.0.0/24 --server-ip 172.16.0.1
```

### Large Network (10.x.x.x)

```bash
sudo ./install --subnet 10.100.0.0/16 --server-ip 10.100.0.1
```

### Small Network (/28 subnet)

```bash
sudo ./install --subnet 192.168.99.0/28 --server-ip 192.168.99.1
```

## Automated Client Management

When generating client configurations with `--client`, the script automatically:

1. **🔍 Auto-detects server's public IP** - No need to manually configure endpoints
2. **📝 Adds client to server config** - Client peer is automatically added to server configuration
3. **🔢 Auto-assigns IP addresses** - Finds next available IP in the subnet
4. **🔄 Conflict detection** - Avoids IP conflicts with existing clients
5. **📱 QR code generation** - Creates QR codes for easy mobile setup (if qrencode installed)
6. **🌍 Geo-optimized DNS** - Automatically selects best DNS servers based on server location
7. **🔄 Auto-restart service** - Automatically restarts WireGuard service to apply new configurations

### DNS Optimization

The script automatically detects the server's location and optimizes DNS servers:

- **🇨🇳 China**: `223.5.5.5, 119.29.29.29` (Alibaba DNS, Tencent DNS)
- **🇷🇺 Russia**: `77.88.8.8, 77.88.8.1` (Yandex DNS)
- **🇩🇪 Germany/EU**: `9.9.9.9, 149.112.112.112` (Quad9)
- **🌍 Global**: `1.1.1.1, 8.8.8.8` (Cloudflare, Google)

You can override with custom DNS: `--dns "208.67.222.222, 208.67.220.220"`

### Example Workflow

```bash
# Option 1: Full installation
sudo ./install --subnet 192.168.100.0/24 --server-ip 192.168.100.1

# Option 2: Create configuration first, install later
sudo ./install --server-only --subnet 192.168.100.0/24 --server-ip 192.168.100.1
sudo ./install  # Install WireGuard with existing config

# Generate first client (gets 192.168.100.2, server IP auto-detected, service auto-restarted)
sudo ./install --client phone

# Generate second client (gets 192.168.100.3, added to server config, service auto-restarted)
sudo ./install --client laptop

# Check status (service should already be running)
sudo systemctl status wg-quick@wg0
```

## Starting the Service

```bash
# Start WireGuard
sudo systemctl start wg-quick@wg0

# Check status
sudo systemctl status wg-quick@wg0

# Enable auto-start
sudo systemctl enable wg-quick@wg0
```

## QR Code Support

Install `qrencode` for easy mobile client setup:

```bash
# Ubuntu/Debian
sudo apt install qrencode

# CentOS/RHEL/Fedora
sudo dnf install qrencode

# Generate QR code for existing client
qrencode -t ansiutf8 < /etc/wireguard/clients/client1.conf
```

## Troubleshooting

1. **Check WireGuard status**: `sudo wg show`
2. **Check service logs**: `sudo journalctl -u wg-quick@wg0`
3. **Verify IP forwarding**: `cat /proc/sys/net/ipv4/ip_forward`
4. **Check iptables rules**: `sudo iptables -L -n -v`

## Security Notes

- All private keys are set to 600 permissions (owner read/write only)
- Key directories are set to 700 permissions
- Client configs include DNS for leak protection
- Server uses dynamic interface detection for NAT rules
