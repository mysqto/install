# Snell

`Surge/Snell/install` installs `snell-server`, the Snell proxy server for Surge clients, on a Linux host. It can also install [shadow-tls](https://github.com/ihciah/shadow-tls) in front of Snell. The script downloads the latest Snell release from the Surge knowledge base and registers systemd services. The script runs on Linux only, because upstream ships no macOS build of `snell-server`.

## Requirements

- Linux with systemd, as root.
- For Snell: `i386`, `amd64`, `aarch64`, or `armv7l`.
- For shadow-tls: `x86_64`, `aarch64`, or `armv7l`.
- A package manager: `apt`, `yum`, `pacman`, or `apk`. The script installs `wget`, `curl`, `unzip`, and `ping` with it.

## Usage

Download the installer:

```bash
curl -sL debian.lol/Surge/Snell/install -o snell-install && chmod +x snell-install
```

Install Snell with a random port and PSK:

```bash
sudo ./snell-install
```

Install Snell with shadow-tls:

```bash
sudo ./snell-install --shadow-tls
```

Install with fixed values:

```bash
sudo ./snell-install --snell-port 8443 --snell-psk 'your-psk' --obfs tls --obfs-host apple.com
```

`im -stls` runs this installer with `--shadow-tls` and sends the arguments after `-stls` to it. [bgc](../README.md#bgc) uses `im -stls` to set up servers.

Before it installs, the script prints the port, PSK, obfs host, DNS servers, and the shadow-tls port and password. Copy these values into your Surge profile, or run [gc](../README.md#gc) to generate the proxy line.

## Options

| Flag | Default | What it does |
|------|---------|--------------|
| `-sp`, `--snell-port` | from the configuration, or a random port 10000 to 65535 | Snell listen port |
| `-spk`, `--snell-psk` | from the configuration, or generated | Snell PSK |
| `-sv`, `--snell-version` | from the configuration, or `5` | Snell protocol version in the configuration |
| `-o`, `--obfs` | `http` | Obfuscation, `http` or `tls` |
| `-h`, `--obfs-host` | from the configuration, or a random host from `microsoft.com`, `apple.com`, `gateway.icloud.com` | Obfuscation host |
| `-d`, `--dns` | from the configuration, or the two fastest servers | DNS servers for `snell-server`, comma-separated |
| `-s`, `--shadow-tls` | on if shadow-tls is already installed | Installs shadow-tls in front of Snell |
| `-stp`, `--shadow-tls-port` | from the configuration, or a random port that is not the Snell port | shadow-tls listen port |
| `-spw`, `--shadow-tls-password` | from the configuration, or generated | shadow-tls password |
| `-6`, `--ipv6` | on | Sets `ipv6 = true`. IPv6 is always on |
| `-t`, `--tfo` | on | Sets `tfo = true`. Do not pass this flag. See [Notes](#notes) |

"From the configuration" means the value in `/etc/snell/snell-server.conf` or `/etc/default/shadow-tls` from an earlier install. When you run the script again with no flags, it keeps the port, PSK, version, and DNS servers.

To pick DNS servers, the script pings 1.1.1.1, 1.0.0.1, 8.8.8.8, 8.8.4.4, 9.9.9.9, 208.67.222.222, 223.5.5.5, 119.29.29.29, 114.114.114.114, and 180.76.76.76. It keeps the two with the lowest average time. If no server replies, it uses `1.1.1.1,8.8.8.8`.

The script has no `--help` flag. `-h` sets the obfs host.

## What it changes

- `/usr/local/bin/snell-server`: the Snell binary. If the installed version is the latest, the script does not download it again.
- `/etc/snell/snell-server.conf`: the Snell configuration, with the PSK. Snell listens on `::0:<port>`, and metrics are on.
- `/lib/systemd/system/snell-server.service`: the Snell service, enabled and restarted.
- With shadow-tls:
  - `/usr/local/bin/shadow-tls`: the shadow-tls binary from the latest GitHub release.
  - `/etc/default/shadow-tls`: the shadow-tls port, password, Snell port, and obfs host.
  - `/lib/systemd/system/shadow-tls.service`: the shadow-tls service, enabled and restarted. It runs `shadow-tls --v3 server` on `::0:<shadow-tls port>` and forwards to Snell on `127.0.0.1:<snell port>`.
- Packages: `wget`, `curl`, `unzip`, and `iputils-ping` or `iputils`.

Both services run with `DynamicUser=true` and `CAP_NET_BIND_SERVICE`.

## Notes

- Do not pass `-t` or `--tfo`. The argument parser does not shift past this flag, so the script never stops. TFO is on by default.
- If you install shadow-tls, the script sets `obfs` to `tls`.
- If you run the script again without `-o` and without shadow-tls, it sets `obfs` back to `http`. The script does not read `obfs` from the earlier configuration.
- If the script downloads a new Snell release, it writes the major version of that release to the configuration. This replaces the `--snell-version` value. The value stays only if the latest release is already installed.
- If no version is in the configuration, the script prints `use 4 as default` but writes version `5`.
- With shadow-tls, Snell still listens on all addresses on its own port. Block the Snell port in your firewall to accept connections through shadow-tls only. The script does not change firewall rules.
- Keep the configuration files private. They hold the PSK and the shadow-tls password. The script prints both values to the terminal.
- On Alpine, the package step runs `apk add --no-cache -y`. `apk` has no `-y` option, so that step fails.
- The script has no uninstall mode.
