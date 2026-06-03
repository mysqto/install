# install

A collections of scripts for daily use

## debian

Used to install any official supported version of debian on almost all cloud services, like Oracle Cloud, Linode, Digital Ocean, etc.

* Supports the following architectures: amd64, arm64, i386, powerpc64le.
* Automatically provision the system:
  * create new user
  * install necessary packages
  * configure system
* usage:

  ```bash
  curl -sL debian.lol/debian -o debian &&                             \
    chmod +x debian &&                                                \
    ./debian --user new_user_name                                     \
           --uid 1024                                                 \
           --password your_password_here                              \
           --authorized-keys-url your_authorized_keys_url_here        \
           --cloud                                                    \
           --efi                                                      \
           --hostname some_hostname
  ```

* Add `--tiny` to chain the [tiny](#tiny) post-install minimization (Dropbear,
  ifupdown, journald → busybox syslog, etc.) so the freshly installed system
  reboots into a ~38 MB-RAM / ~275 MB-disk footprint. Distinct from `--minimal`,
  which only enables a smaller package set + cloud kernel.

## tiny

Post-install minimization for Debian 13 KVM VPS instances. Implements the eight
stages from [TierHive's minimal Debian 13 guide][tiny-ref]: GRUB cmdline tweaks,
OpenSSH → Dropbear, cloud-init/python purge, package strip with dpkg `nodoc`,
systemd-resolved/networkd → ifupdown, service masking, dependency-only
initramfs + module blacklist, and sysctl tuning with journald → busybox syslog.

[tiny-ref]: https://tierhive.com/blog/tierhive-howto/debian-13-minimal-guide-reduce-ram-to-38mb-and-disk-to-275mb

```bash
# all stages, after a fresh install
curl -sL debian.lol/tiny -o tiny && chmod +x tiny
./tiny --all --yes

# pick stages individually
./tiny --grub --strip-packages --tune --yes

# safer Stage 5 with explicit network params
./tiny --ifupdown --interface ens3 --ip 1.2.3.4/24 --gateway 1.2.3.1 --yes
```

Each stage is idempotent and individually selectable. Stage 5 is skipped when
the interface/IP/gateway can't be resolved, so the script never strands a
remote box. `--keep-mitigations` and `--keep-ipv6` opt out of the most
aggressive GRUB cmdline changes.

## ubuntu

Similar to debian, only support version lower or equal to 20.04

## provision

Install necessary packages, configure system and users

## WireGuard VPN

Advanced WireGuard VPN installation and management scripts with GeoIP-based split tunneling.

### WireGuard Server (`wireguard/install`)
- **Multi-distribution support**: Ubuntu, Debian, CentOS, RHEL, Fedora, Rocky Linux, AlmaLinux, Arch, openSUSE, Alpine
- **Automatic key generation**: Server and client keys generated automatically  
- **Dynamic client management**: Easy client addition with unique IP assignment
- **Network configuration**: Automatic IP forwarding and iptables setup

```bash
# Basic server installation
sudo ./wireguard/install --server-only

# Generate client configuration  
sudo ./wireguard/install --client alice

# Custom subnet and settings
sudo ./wireguard/install --server-ip 192.168.100.1 --subnet 192.168.100.0/24
```

### Advanced Client Generator (`wireguard/wg-client`)
- **GeoIP-based split tunneling**: Route local country traffic directly, international via VPN
- **Country-specific DNS optimization**: Auto-selects optimal DNS servers by location
- **Automatic routing scripts**: Creates PostUp/PostDown scripts for split tunneling

```bash
# Basic client config (full tunnel)
./wireguard/wg-client --client-ip 10.0.0.2 --server-ip YOUR_SERVER --server-key "SERVER_KEY" -o client.conf

# Split tunneling (US traffic local, others via VPN)
./wireguard/wg-client --client-ip 10.0.0.2 --server-ip YOUR_SERVER --server-key "SERVER_KEY" --local-country US -o client.conf
```

### Docker Testing Environment (`wireguard/test-docker.sh`)
- **Comprehensive testing**: Tests server installation and client generation
- **Isolated environment**: Docker containers for safe testing
- **Automated validation**: 8 test categories covering all functionality

```bash
# Run full test suite
./wireguard/test-docker.sh

# Setup for manual testing
./wireguard/test-docker.sh --setup-only
```

## Shadowsocks Rust Client

Simple and focused Shadowsocks Rust client installer with SOCKS5 proxy and systemd integration.

### Features (`ss-rust-client`)  
- **Simple installation**: One command installs everything needed
- **Latest shadowsocks-rust**: Downloads from GitHub releases automatically  
- **SOCKS5 proxy setup**: Local proxy on 127.0.0.1:1080 by default
- **Plugin support**: Auto-installs obfs-local for HTTP/TLS obfuscation
- **Security hardened**: Systemd service with security restrictions
- **Multi-distribution**: Works on all major Linux distributions

```bash
# Basic installation
sudo ./ss-rust-client -s your-server.com -p 8388 -k 'your-password'

# With HTTP obfuscation (bypass-optimized)
sudo ./ss-rust-client -s server.com -p 8388 -k 'password' \
  --plugin obfs-local --plugin-opts 'obfs=http;obfs-host=www.bing.com'

# Custom settings
sudo ./ss-rust-client -s server.com -p 8388 -k 'password' \
  -l 0.0.0.0 -P 1090 -m aes-256-gcm --service-name ss-backup
```

### Encryption Methods
- **ChaCha20-IETF-Poly1305** (default) - Fast and secure
- **AES-256-GCM** - Hardware accelerated on modern CPUs
- **AEAD-2022** ciphers - Latest standards

### Client Applications
Configure any SOCKS5-compatible application:
- **Browsers**: Chrome, Firefox, Safari, Edge
- **System-wide**: `export https_proxy=socks5://127.0.0.1:1080`
- **Testing**: `curl --socks5-hostname 127.0.0.1:1080 https://httpbin.org/ip`

## other scripts
