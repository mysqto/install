# V2Ray Installation Script

Clean and small script to install V2Ray client & server.

## Features

- ✅ Auto-downloads latest V2Ray from official GitHub releases
- ✅ Supports multiple architectures (x86_64, aarch64, armv7)
- ✅ Server and client modes
- ✅ Multiple protocols (VMess, VLess)
- ✅ Multiple network types (TCP, WebSocket, HTTP, QUIC)
- ✅ Optional TLS support
- ✅ Custom installation prefix
- ✅ Systemd service management
- ✅ Auto-generates UUID and random ports
- ✅ VMess link generation for easy client import

## Quick Start

### Install Server

```bash
# Basic server installation
curl -sL https://debian.lol/v2ray/install | sudo bash -s -- --server

# Server with custom port
curl -sL https://debian.lol/v2ray/install | sudo bash -s -- --server --port 10086

# Server with WebSocket + TLS
curl -sL https://debian.lol/v2ray/install | sudo bash -s -- --server --network ws --tls

# Server with custom prefix
curl -sL https://debian.lol/v2ray/install | sudo bash -s -- --server --prefix /opt/v2ray
```

### Install Client

```bash
# Basic client installation (proxy mode)
curl -sL https://debian.lol/v2ray/install | sudo bash -s -- --client \
  --address 1.2.3.4 --port 10086 --uuid your-uuid-here

# Client with forced IPv4
curl -sL https://debian.lol/v2ray/install | sudo bash -s -- --client \
  --address 1.2.3.4 --port 10086 --uuid your-uuid-here -4

# Client with TUN mode (transparent proxy - routes all traffic)
curl -sL https://debian.lol/v2ray/install | sudo bash -s -- --client \
  --address 1.2.3.4 --port 10086 --uuid your-uuid-here --tun

# Client with WebSocket + TLS and forced IPv6
curl -sL https://debian.lol/v2ray/install | sudo bash -s -- --client \
  --address example.com --port 443 --uuid your-uuid-here --network ws --tls -6
```

## Using with `im` script

```bash
# Install v2ray server
sudo im --v2ray-server

# Install v2ray server with custom port
sudo im --v2ray-server --port 8443

# Install v2ray client
sudo im --v2ray-client --address example.com --port 443 --uuid xxx
```

## Options

```
-s, --server              Install as server
-c, --client              Install as client
-p, --port PORT           Listen port (server) or server port (client)
-u, --uuid UUID           UUID for authentication
-a, --address ADDR        Server address (required for client)
-4, --ipv4                Force IPv4 for downloads
-6, --ipv6                Force IPv6 for downloads
--prefix PATH             Installation prefix (default: /usr/local)
--protocol PROTO          Protocol: vmess, vless (default: vmess)
--network NET             Network type: tcp, ws, http, quic (default: tcp)
--tls                     Enable TLS
--ws-path PATH            WebSocket path (default: /v2ray)
--tun                     Enable TUN mode for client (transparent proxy)
--tun-address ADDR        TUN interface address (default: 10.0.85.1/24)
--tun-gateway GW          TUN gateway address (default: 10.0.85.1)
-h, --help                Show help message
```

## File Locations

With default prefix `/usr/local`:
- Binary: `/usr/local/bin/v2ray`
- Config: `/usr/local/etc/v2ray/config.json`
- Service: `/etc/systemd/system/v2ray.service`

## Service Management

```bash
# Check status
systemctl status v2ray

# Start/stop/restart
systemctl start v2ray
systemctl stop v2ray
systemctl restart v2ray

# View logs
journalctl -u v2ray -f

# Enable/disable auto-start
systemctl enable v2ray
systemctl disable v2ray
```

## Client Modes

### Proxy Mode (Default)
- SOCKS5 proxy: `127.0.0.1:1080`
- HTTP proxy: `127.0.0.1:1081`
- Configure applications to use these proxies

### TUN Mode (Transparent Proxy)
- Creates a virtual network interface
- Routes all system traffic through V2Ray automatically
- No application configuration needed
- Requires elevated privileges (root/sudo)
- Ideal for system-wide VPN-like behavior

## Client Configuration

After server installation, you'll receive:
- Server port and UUID
- VMess connection link (for easy import to clients)
- Connection details for both proxy and TUN modes

## Examples

### Simple Server Setup

```bash
sudo ./install --server
```

Output includes:
```
Port: 12345
UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
VMess Link: vmess://...
```

### Advanced Server with WebSocket

```bash
sudo ./install --server --port 443 --network ws --tls
```

Note: TLS requires valid certificates at `/path/to/certificate.crt` and `/path/to/private.key`

### Client Setup (Proxy Mode)

```bash
sudo ./install --client \
  --address your-server.com \
  --port 12345 \
  --uuid xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Then configure your applications to use:
- SOCKS5: `127.0.0.1:1080`
- HTTP: `127.0.0.1:1081`

### Client Setup (TUN Mode)

```bash
# Install with TUN mode
sudo ./install --client \
  --address your-server.com \
  --port 12345 \
  --uuid xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --tun

# Start V2Ray (requires root for TUN interface)
sudo /usr/local/bin/v2ray run -config /usr/local/etc/v2ray/config.json

# All system traffic now goes through V2Ray automatically!
```

**TUN Mode Benefits:**
- No need to configure individual applications
- System-wide transparent proxying
- Works with all network applications
- VPN-like experience

**TUN Mode Requirements:**
- Root/sudo privileges
- CAP_NET_ADMIN capability
- Linux kernel with TUN/TAP support

## Troubleshooting

### Check if V2Ray is running

```bash
systemctl status v2ray
```

### View logs

```bash
journalctl -u v2ray -n 50
```

### Test configuration

```bash
/usr/local/bin/v2ray test -config /usr/local/etc/v2ray/config.json
```

### Reinstall/Update

Just run the installation script again. It will:
- Check for newer versions
- Preserve existing UUID and port
- Update only if needed

## Links

- [V2Ray Official](https://www.v2fly.org/)
- [V2Ray Core GitHub](https://github.com/v2fly/v2ray-core)

