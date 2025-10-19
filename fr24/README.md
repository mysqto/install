# FlightRadar24 Feeder Installation Script

Clean installation script for FlightRadar24 ADS-B feeder.

## Features

- ✅ Auto-downloads latest FR24Feed from official repository
- ✅ Supports multiple architectures (x86_64, i386, armv7l, arm64)
- ✅ Custom installation prefix
- ✅ Systemd service management
- ✅ Auto-generates configuration
- ✅ IPv4/IPv6 support

## Quick Start

### Install via im Script

```bash
# Basic installation
sudo im -fr24 --key YOUR_SHARING_KEY

# With location
sudo im -fr24 --key YOUR_KEY --lat 51.5074 --lon -0.1278 --alt 50

# With IPv4
sudo im -4 -fr24 --key YOUR_KEY --lat 51.5 --lon -0.1
```

### Install Directly

```bash
# Basic installation
curl -sL https://debian.lol/fr24/install | sudo bash -s -- --key YOUR_KEY

# With location
curl -sL https://debian.lol/fr24/install | sudo bash -s -- \
  --key YOUR_KEY --lat 51.5074 --lon -0.1278 --alt 50

# With custom prefix
curl -sL https://debian.lol/fr24/install | sudo bash -s -- \
  --key YOUR_KEY --prefix /opt/fr24
```

## Options

```
-k, --key KEY             Sharing/FR24 key (required for feeding)
--lat LATITUDE            Receiver latitude
--lon LONGITUDE           Receiver longitude
--alt ALTITUDE            Receiver altitude in meters
-r, --receiver TYPE       Receiver type (default: dvbt)
                          Options: dvbt, beast, radarcape, avr, sbs
-v, --version VERSION     FR24Feed version (default: 1.0.54-0)
--prefix PATH             Installation prefix (default: /usr/local)
-4, --ipv4                Force IPv4 for downloads
-6, --ipv6                Force IPv6 for downloads
-h, --help                Show help message
```

## Getting Your Sharing Key

1. Visit: https://www.flightradar24.com/share-your-data
2. Sign up for a free account
3. Get your sharing key
4. Or run: `/usr/local/bin/fr24feed --signup`

## File Locations

With default prefix `/usr/local`:
- Binary: `/usr/local/bin/fr24feed`
- Config: `/usr/local/etc/fr24feed/fr24feed.ini`
- Service: `/etc/systemd/system/fr24feed.service`

## Service Management

```bash
# Check status
systemctl status fr24feed

# Start/stop/restart
systemctl start fr24feed
systemctl stop fr24feed
systemctl restart fr24feed

# View logs
journalctl -u fr24feed -f

# View statistics
/usr/local/bin/fr24feed --monitor

# Enable/disable auto-start
systemctl enable fr24feed
systemctl disable fr24feed
```

## Configuration

The script creates a basic configuration at `/usr/local/etc/fr24feed/fr24feed.ini`:

```ini
receiver="dvbt"
fr24key="YOUR_KEY"
host="127.0.0.1:30005"
bs="yes"
raw="yes"
logmode="1"
logpath="/var/log/fr24feed"
mlat="yes"
mlat-without-gps="yes"
latitude="51.5074"
longitude="-0.1278"
altitude="50"
```

## Receiver Types

- `dvbt` - DVB-T stick (default)
- `beast` - Mode-S Beast
- `radarcape` - Radarcape
- `avr` - AVR format
- `sbs` - SBS format

## Examples

### Simple Installation

```bash
sudo ./install --key YOUR_KEY
```

### With Location

```bash
sudo ./install \
  --key YOUR_KEY \
  --lat 51.5074 \
  --lon -0.1278 \
  --alt 50
```

### With Custom Settings

```bash
sudo ./install \
  --key YOUR_KEY \
  --lat 51.5 \
  --lon -0.1 \
  --alt 50 \
  --receiver beast \
  --prefix /opt/fr24
```

### With IPv4

```bash
sudo ./install --key YOUR_KEY -4
```

## Requirements

- Linux system (Debian, Ubuntu, etc.)
- ADS-B receiver (RTL-SDR, Mode-S Beast, etc.)
- Internet connection
- Root privileges

## Troubleshooting

### Check if FR24Feed is running

```bash
systemctl status fr24feed
```

### View logs

```bash
journalctl -u fr24feed -n 50
```

### Test manually

```bash
/usr/local/bin/fr24feed --config-file=/usr/local/etc/fr24feed/fr24feed.ini
```

### Run signup

```bash
/usr/local/bin/fr24feed --signup
```

### Monitor statistics

```bash
/usr/local/bin/fr24feed --monitor
```

## Integration with ADS-B Tools

FR24Feed typically connects to:
- dump1090 (port 30005)
- readsb (port 30005)
- Other Mode-S decoders

Make sure your decoder is running first:
```bash
# Check if decoder is running
netstat -tuln | grep 30005

# Or
ss -tuln | grep 30005
```

## Links

- [FlightRadar24 Data Sharing](https://www.flightradar24.com/share-your-data)
- [FR24Feed Documentation](https://www.flightradar24.com/build-your-own)
- [Repository](https://repo.feed.flightradar24.com/)

## Notes

- The script downloads binaries from the official FR24 repository
- Sharing key is optional during installation but required for feeding
- You can run `fr24feed --signup` after installation to get a key
- Location information improves MLAT performance

