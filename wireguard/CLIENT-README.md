# WireGuard Advanced Client Generator

An advanced WireGuard client configuration generator with GeoIP-based split tunneling support.

## Features

✅ **Automatic key generation** - Generates client keypairs if not provided  
✅ **GeoIP-based split tunneling** - Route local country traffic directly, international via VPN  
✅ **Country-specific DNS optimization** - Auto-selects optimal DNS servers by location  
✅ **Comprehensive validation** - Validates IPs, ports, and country codes  
✅ **QR code support** - Generates QR codes for mobile import  
✅ **Routing script generation** - Creates PostUp/PostDown scripts for split tunneling  

## Basic Usage

### Full Tunnel Mode (All traffic via VPN)

```bash
./wg-client \
  --client-ip 10.0.0.2 \
  --server-ip 203.0.113.1 \
  --server-key "SERVER_PUBLIC_KEY_HERE" \
  -o client.conf
```

### Split Tunneling Mode (Local country direct, others via VPN)

```bash
# Route US traffic locally, international traffic via VPN
./wg-client \
  --client-ip 10.0.0.2 \
  --server-ip 203.0.113.1 \
  --server-key "SERVER_PUBLIC_KEY_HERE" \
  --local-country US \
  -o client-us.conf

# Route China traffic locally with optimized DNS
./wg-client \
  --client-ip 10.0.0.2 \
  --server-ip 203.0.113.1 \
  --server-key "SERVER_PUBLIC_KEY_HERE" \
  --local-country CN \
  -o client-cn.conf
```

## Command Line Options

### Required Options
- `--client-ip IP` - Client VPN IP address
- `--server-ip IP` - Server public IP address  
- `--server-key KEY` - Server public key
- `-o, --output FILE` - Output configuration file

### Optional Options
- `--client-key KEY` - Client private key (auto-generated if not provided)
- `--port PORT` - Server port (default: 51820)
- `--dns SERVERS` - DNS servers (auto-selected if not provided)
- `--local-country CODE` - Country code for split tunneling (e.g., US, CN, DE)
- `--debug` - Enable debug output
- `--help` - Show help message

## Split Tunneling Countries

The script supports any ISO 2-letter country code and includes optimizations for:

- **🇺🇸 US (United States)** - DNS: `1.1.1.1, 9.9.9.9`
- **🇨🇳 CN (China)** - DNS: `223.5.5.5, 119.29.29.29` (Alibaba, Tencent)
- **🇩🇪 DE (Germany)** - DNS: `9.9.9.9, 149.112.112.112` (Quad9)  
- **🇷🇺 RU (Russia)** - DNS: `77.88.8.8, 77.88.8.1` (Yandex)
- **🌍 Global fallback** - DNS: `1.1.1.1, 8.8.8.8` (Cloudflare, Google)

## How Split Tunneling Works

1. **Downloads country IP ranges** from reliable sources (ipdeny.com)
2. **Generates PostUp/PostDown scripts** with country-specific routes  
3. **Creates WireGuard config** that routes international traffic through VPN
4. **Local country traffic** bypasses VPN and goes directly through default gateway

### Example Generated Files

For split tunneling, the script creates:
- `client.conf` - Main WireGuard configuration
- `client-post-up.sh` - Script to add local country routes
- `client-post-down.sh` - Script to remove local country routes

## Advanced Examples

### Custom DNS and Port
```bash
./wg-client \
  --client-ip 10.0.0.2 \
  --server-ip 203.0.113.1 \
  --server-key "KEY" \
  --port 51821 \
  --dns "1.1.1.1,8.8.8.8" \
  -o client.conf
```

### Using Existing Client Key
```bash
./wg-client \
  --client-ip 10.0.0.2 \
  --server-ip 203.0.113.1 \
  --server-key "SERVER_KEY" \
  --client-key "CLIENT_PRIVATE_KEY" \
  -o client.conf
```

### Debug Mode
```bash
DEBUG=1 ./wg-client \
  --client-ip 10.0.0.2 \
  --server-ip 203.0.113.1 \
  --server-key "KEY" \
  --local-country US \
  --debug \
  -o client.conf
```

## Generated Configuration Examples

### Full Tunnel Configuration
```ini
[Interface]
PrivateKey = CLIENT_PRIVATE_KEY
Address = 10.0.0.2/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = 203.0.113.1:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### Split Tunnel Configuration (US)
```ini
[Interface]
PrivateKey = CLIENT_PRIVATE_KEY
Address = 10.0.0.2/32
DNS = 1.1.1.1, 9.9.9.9
PostUp = /path/to/client-post-up.sh
PostDown = /path/to/client-post-down.sh

[Peer]
PublicKey = SERVER_PUBLIC_KEY  
Endpoint = 203.0.113.1:51820
AllowedIPs = 0.0.0.0/5, 8.0.0.0/7, 11.0.0.0/8, ...
PersistentKeepalive = 25
```

## Requirements

- **WireGuard** - Required for key generation (`wg` command)
- **curl** - For downloading country IP ranges (auto-installed if missing)
- **qrencode** - Optional, for QR code generation

## Installation

1. Make the script executable:
```bash
chmod +x wg-client
```

2. Run with desired options:
```bash
./wg-client --help
```

## Use Cases

### 🏠 Home User in US
Route US traffic directly (for speed), international traffic via VPN (for privacy):
```bash
./wg-client --client-ip 10.0.0.2 --server-ip VPN_SERVER --server-key "KEY" --local-country US -o us-client.conf
```

### 🏢 Business User in China  
Route China traffic directly (for compliance), international traffic via VPN (for access):
```bash
./wg-client --client-ip 10.0.0.2 --server-ip VPN_SERVER --server-key "KEY" --local-country CN -o cn-client.conf
```

### 🌐 Privacy-focused User
Route all traffic via VPN (maximum privacy):
```bash
./wg-client --client-ip 10.0.0.2 --server-ip VPN_SERVER --server-key "KEY" -o private-client.conf
```

## Troubleshooting

1. **Country IP download fails**: Check internet connection and try with `--debug`
2. **Split tunneling not working**: Verify PostUp/PostDown scripts have execute permissions
3. **Key generation fails**: Ensure WireGuard is installed (`apt install wireguard`)
4. **Invalid country code**: Use 2-letter ISO codes (US, CN, DE, etc.)

## Security Notes

- All generated private keys have 600 permissions (owner read/write only)
- Configuration files have 600 permissions  
- Country IP ranges downloaded from trusted sources
- No sensitive data logged (use `--debug` only for troubleshooting)
