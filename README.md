# install

This repository holds install scripts for servers and workstations. GitHub Pages serves the `gh-pages` branch at `debian.lol`, so each script has a short URL. For example, `debian.lol/frp/install` serves `frp/install`.

Download a script, then read its README before you run it:

```bash
curl -sL debian.lol/<path> -o <file> && chmod +x <file>
```

Each component has its own README. The scripts at the repository root cannot move into folders, because that change breaks their URLs. Their READMEs are at the root as `<NAME>-README.md`.

## Operating system installers

| Component | README | What it does |
|-----------|--------|--------------|
| `debian` | [DEBIAN-README.md](DEBIAN-README.md) | Reinstalls a running Linux host with an official Debian release, through a preseeded netboot installer that starts from GRUB. It can run `provision` and `tiny` after the install. |
| `ubuntu` | [UBUNTU-README.md](UBUNTU-README.md) | Reinstalls a running Linux host with Ubuntu 20.04 LTS (focal), through a preseeded netboot installer that starts from GRUB. |
| `tiny` | [TINY-README.md](TINY-README.md) | Shrinks a fresh Debian 13 KVM VPS to about 38 MB of RAM and 275 MB of disk. You select its eight stages with flags. |
| `provision` | [PROVISION-README.md](PROVISION-README.md) | Upgrades a new Debian or Ubuntu server and creates a user with SSH keys and sudo rules. It can also add fish, Docker, Go, Shadowsocks, Snell with Shadow-TLS, BBR and network changes. |
| `im` | [IM-README.md](IM-README.md) | The entry point on a server. It does maintenance, or it runs the installer of another component. Each run does one action. |

## Tools and runtimes

| Component | README | What it does |
|-----------|--------|--------------|
| `docker` | [DOCKER-README.md](DOCKER-README.md) | Installs Docker Engine, buildx and compose from the official Docker apt repository on Debian or Ubuntu. |
| `colima` | [colima/README.md](colima/README.md) | Installs Colima, the Docker CLI, its plugins and credential helpers on macOS. It runs the VM by hand, per user, or shared by several users. |
| `go` | [GO-README.md](GO-README.md) | Installs the latest Go from go.dev on Linux or macOS. `--setup` adds gocode, golangci-lint and goimports. |

## Proxies and tunnels

| Component | README | What it does |
|-----------|--------|--------------|
| `ss-rust` | [SS-RUST-README.md](SS-RUST-README.md) | Installs the shadowsocks-rust server and simple-obfs. `--setup` also writes the configuration and starts a systemd service. |
| `iss` | [ISS-README.md](ISS-README.md) | A short wrapper that runs the `ss-rust` installer with an optional `--password`. |
| `ss-rust-client`, `ss-client` | [SS-CLIENT-README.md](SS-CLIENT-README.md) | Installs a shadowsocks-rust client with a local SOCKS5 proxy and a systemd service. The two files are the same script. |
| `ss-libev` | [SS-LIBEV-README.md](SS-LIBEV-README.md) | Builds a shadowsocks-libev server with simple-obfs from source on Debian or Ubuntu, and runs it as a systemd service. |
| `ss2any` | [ss2any/README.md](ss2any/README.md) | A Docker container with a Shadowsocks endpoint that sends traffic through an upstream proxy given as one URL. |
| `v2ray` | [v2ray/README.md](v2ray/README.md) | Installs the V2Ray client and server. |
| `Surge/Snell` | [Surge/Snell/README.md](Surge/Snell/README.md) | Installs `snell-server`, and optionally shadow-tls, on Linux with systemd. |
| `Surge` | [Surge/README.md](Surge/README.md) | `gc` and `bgc` make Surge proxy lines from servers over SSH. `Rules/Oracle.list` is a Surge rule list for Oracle domains. |
| `wireguard` | [wireguard/README.md](wireguard/README.md) | Installs a WireGuard server and makes client configurations, with optional GeoIP split tunneling. |
| `wg-ss` | [wg-ss/README.md](wg-ss/README.md) | A Docker container that joins a WireGuard peer as a client and serves Shadowsocks, so traffic leaves through the tunnel. |
| `tailscale` | [tailscale/README.md](tailscale/README.md) | A Docker container that joins your tailnet and serves Shadowsocks as the entry point. |
| `frp` | [frp/README.md](frp/README.md) | Installs the frp server (`frps`) or client (`frpc`) to expose ports behind NAT, with systemd on Linux and launchd on macOS. |
| `socat` | [socat/README.md](socat/README.md) | A systemd service that forwards local TCP and UDP ports to remote hosts, from a list in `/etc/socatrc`. |

## Network and host services

| Component | README | What it does |
|-----------|--------|--------------|
| `sshd` | [sshd/README.md](sshd/README.md) | A hardened SSH server in one Docker container, with key-only login and a chosen or random port. |
| `ddns` | [ddns/README.md](ddns/README.md) | A cron job that keeps a Cloudflare DNS record pointed at the public IP of the host. |
| `fr24` | [fr24/README.md](fr24/README.md) | Installs the FlightRadar24 ADS-B feeder. |
| `piware` | [piware/README.md](piware/README.md) | Adds the FlightAware PiAware APT repository and signing key on Debian or Ubuntu. |

## Other files

`authorized_keys` holds public SSH keys. No script reads it by default. To use it, give `--authorized-keys-url debian.lol/authorized_keys` to `debian`. `CNAME` sets the `debian.lol` domain for GitHub Pages. `.github/workflows/pages.yml` deploys the branch to GitHub Pages on each push.

## License

See [LICENSE](LICENSE).
