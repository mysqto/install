# Shadowsocks Rust Client

Simple and focused Shadowsocks Rust client installer with SOCKS5 proxy and systemd integration.

## Features

✅ **Simple Installation** - One command installs everything needed  
✅ **Latest Version** - Downloads latest shadowsocks-rust from GitHub releases  
✅ **SOCKS5 Proxy** - Local proxy on 127.0.0.1:1080 by default  
✅ **Plugin Support** - Auto-installs obfs-local for HTTP/TLS obfuscation  
✅ **Systemd Service** - Secure service with automatic startup  
✅ **Multi-Distribution** - Works on all major Linux distributions  

## Quick Start

### Basic Installation
```bash
sudo ./ss-rust-client -s your-server.com -p 8388 -k 'your-password'
```

### With HTTP Obfuscation (Recommended)
```bash
sudo ./ss-rust-client -s your-server.com -p 8388 -k 'your-password' \
  --plugin obfs-local --plugin-opts 'obfs=http;obfs-host=www.bing.com'
```

## Command Line Options

### Required Parameters
- `-s, --server HOST` - Server hostname or IP address
- `-p, --server-port PORT` - Server port number  
- `-k, --password PASS` - Server password

### Optional Parameters
- `-h, --help` - Show help message
- `-m, --method METHOD` - Encryption method (default: chacha20-ietf-poly1305)
- `-l, --local-addr ADDR` - Local bind address (default: 127.0.0.1)
- `-P, --local-port PORT` - Local SOCKS5 port (default: 1080)
- `--plugin PLUGIN` - Plugin name (obfs-local for obfuscation)
- `--plugin-opts OPTS` - Plugin configuration options
- `-c, --config FILE` - Configuration file path (default: /etc/shadowsocks/client.json)
- `--service-name NAME` - Systemd service name (default: ss-client)
- `--no-start` - Don't start the service after installation

## Encryption Methods

- `chacha20-ietf-poly1305` (default) - Fast and secure
- `aes-256-gcm` - Hardware accelerated on modern CPUs
- `aes-128-gcm` - Faster AES variant
- `xchacha20-ietf-poly1305` - Extended ChaCha20
- `2022-blake3-chacha20-poly1305` - Latest AEAD-2022 standard

## Plugin Configuration

### HTTP Obfuscation
```bash
--plugin obfs-local --plugin-opts "obfs=http;obfs-host=www.microsoft.com"
```

### TLS Obfuscation
```bash
--plugin obfs-local --plugin-opts "obfs=tls;obfs-host=www.apple.com"
```

### Common Obfs Hosts
- `www.bing.com` - Microsoft services
- `www.apple.com` - Apple services  
- `gateway.icloud.com` - iCloud traffic
- `www.microsoft.com` - Microsoft main site
- `www.cloudflare.com` - CloudFlare CDN

## Usage Examples

### Standard Setup
```bash
# Basic installation with default settings
sudo ./ss-rust-client -s ss.example.com -p 8388 -k 'MySecurePassword'

# Custom encryption method
sudo ./ss-rust-client -s ss.example.com -p 8388 -k 'password' -m aes-256-gcm

# Bind to all interfaces (LAN accessible)
sudo ./ss-rust-client -s ss.example.com -p 8388 -k 'password' -l 0.0.0.0
```

### Bypass-Optimized Configurations
```bash
# China optimized (port 443, TLS obfuscation)
sudo ./ss-rust-client -s server.com -p 443 -k 'password' \
  --plugin obfs-local --plugin-opts 'obfs=tls;obfs-host=www.apple.com'

# Iran optimized (HTTP obfuscation with common host)
sudo ./ss-rust-client -s server.com -p 8388 -k 'password' \
  --plugin obfs-local --plugin-opts 'obfs=http;obfs-host=www.bing.com'

# General bypass (CloudFlare host)
sudo ./ss-rust-client -s server.com -p 443 -k 'password' \
  --plugin obfs-local --plugin-opts 'obfs=tls;obfs-host=www.cloudflare.com'
```

### Multiple Instances
```bash
# Main connection
sudo ./ss-rust-client -s server1.com -p 8388 -k 'pass1' --service-name ss-main -P 1080

# Backup connection  
sudo ./ss-rust-client -s server2.com -p 8388 -k 'pass2' --service-name ss-backup -P 1081
```

## Service Management

### Systemd Commands
```bash
# Start service
sudo systemctl start ss-client

# Stop service
sudo systemctl stop ss-client

# Check status
sudo systemctl status ss-client

# View logs
sudo journalctl -u ss-client -f

# Restart service
sudo systemctl restart ss-client
```

### Configuration
- **Config file**: `/etc/shadowsocks/client.json`
- **Service file**: `/etc/systemd/system/ss-client.service`
- **Logs**: `journalctl -u ss-client`

## Client Application Setup

### Browser Configuration
- **Proxy Type**: SOCKS5
- **Address**: 127.0.0.1
- **Port**: 1080
- **Username/Password**: (leave empty)

### System-wide Proxy (Linux)
```bash
export http_proxy=socks5://127.0.0.1:1080
export https_proxy=socks5://127.0.0.1:1080
export all_proxy=socks5://127.0.0.1:1080
```

### Testing Connection
```bash
# Test SOCKS5 proxy
curl --socks5-hostname 127.0.0.1:1080 https://httpbin.org/ip

# Check what IP you're using
curl --socks5-hostname 127.0.0.1:1080 https://ipinfo.io
```

## Troubleshooting

### Common Issues

1. **Service won't start**
   ```bash
   sudo journalctl -u ss-client --no-pager
   sudo systemctl status ss-client
   ```

2. **Can't connect to server**
   ```bash
   # Test server connectivity
   telnet your-server.com 8388
   
   # Test manual connection
   sudo ss-local -c /etc/shadowsocks/client.json -v
   ```

3. **SOCKS5 proxy not working**
   ```bash
   # Check if port is listening
   sudo ss -tln | grep :1080
   
   # Test proxy directly
   curl --socks5-hostname 127.0.0.1:1080 https://httpbin.org/ip
   ```

### Debug Mode
```bash
# Run manually with verbose output
sudo ss-local -c /etc/shadowsocks/client.json -v

# Check service logs in real-time
sudo journalctl -u ss-client -f
```

## What the Script Does

1. **📦 Installs dependencies** using proven package lists
2. **⬇️ Downloads latest shadowsocks-rust** from GitHub releases
3. **🔌 Installs obfs-local plugin** if specified (compiled from source)
4. **📝 Creates configuration file** with proper permissions
5. **🔧 Sets up systemd service** with security hardening
6. **🚀 Starts SOCKS5 proxy** and tests connectivity

## Security Features

- **DynamicUser** - Service runs as unprivileged dynamic user
- **ReadOnlyPaths** - Config directory mounted read-only
- **ProtectSystem** - System directories protected
- **NoNewPrivileges** - Prevents privilege escalation
- **PrivateTmp** - Isolated temporary directories

## Requirements

- **OS**: Linux (Ubuntu 18.04+, Debian 9+, CentOS 7+, Fedora 30+)
- **Architecture**: x86_64, aarch64, i686
- **Privileges**: Root access required for installation
- **Network**: Internet access for downloads

## Generated Configuration Example

```json
{
    "server": "your-server.com",
    "server_port": 8388,
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "your-password",
    "method": "chacha20-ietf-poly1305",
    "timeout": 300,
    "plugin": "obfs-local",
    "plugin_opts": "obfs=http;obfs-host=www.bing.com"
}
```

This simple, focused script provides all the essential functionality without complexity!