# ss-libev

`ss-libev` builds and installs a shadowsocks-libev server with the simple-obfs plugin. It compiles libsodium, mbedTLS, simple-obfs and shadowsocks-libev from source, writes a server configuration, and starts a systemd service. Run it on a Debian or Ubuntu server.

For the newer server based on shadowsocks-rust, see [SS-RUST-README.md](SS-RUST-README.md). For a client, see [SS-CLIENT-README.md](SS-CLIENT-README.md).

## Requirements

- A Debian or Ubuntu host. The script installs its build packages with `apt`.
- systemd.
- A user with `sudo`. The script calls `sudo` for each step that needs root.
- Outbound access to `api.github.com` and `github.com`. The script downloads releases and clones repositories from there.

## Usage

Download the script on the server:

```bash
curl -sL debian.lol/ss-libev -o ss-libev && chmod +x ss-libev
```

Install with random values for the port, the password and the obfs host:

```bash
./ss-libev
```

Install with fixed values:

```bash
./ss-libev --port 8388 --password 'your-password' --obfs-host www.bing.com --dns-server 1.1.1.1
```

The script does not print the port or the password. Read them from the configuration file after the install:

```bash
sudo cat /etc/shadowsocks-libev/config.json
```

You can also run the script through `im`. If the `shadowsocks-libev` service is active, `im -uss` runs `ss-libev` again.

## Options

| Flag | Default | What it does |
|------|---------|--------------|
| `-P`, `--port <port>` | Random, 10000 to 65535 | Server port. |
| `-p`, `--password <pw>` | Random, 32 characters | Server password. |
| `-o`, `--obfs-host <host>` | Random from a fixed list | Host name that simple-obfs uses for HTTP obfuscation. |
| `-d`, `--dns-server <ip>` | `8.8.8.8` | Name server that the server uses. |
| `-lsv`, `--libsodium-version <v>` | Latest GitHub release | libsodium version to build. |
| `-mv`, `--mbedtls-version <v>` | Latest `v2.` tag on GitHub | mbedTLS version to build. |
| `-4`, `--ipv4` | Off | Use IPv4 for downloads. |
| `-6`, `--ipv6` | Off | Use IPv6 for downloads. |

The random obfs host is one of `microsoft.com`, `apple.com`, `gateway.messenger.live.com` and `gateway.icloud.com`.

The script has no `--help` flag. An unknown flag prints a warning, and the install continues.

The environment variables `CURL_OPTS` and `WGET_OPTS` pass extra flags to `curl` and `wget`.

## What it changes

- Packages: it installs the build tools and libraries with `apt`. The list is `gettext build-essential autoconf libtool libpcre2-dev asciidoc xmlto libev-dev libc-ares-dev automake libmbedtls-dev libsodium-dev pkg-config`.
- Libraries and binaries: it installs libsodium, mbedTLS, simple-obfs and shadowsocks-libev under `/usr`.
- Configuration: it writes `/etc/shadowsocks-libev/config.json` and copies `/etc/default/shadowsocks-libev`.
- Service: it installs `/lib/systemd/system/shadowsocks-libev.service`, adds `Restart=on-failure` and `RestartSec=5`, enables the service and starts it.
- Kernel setting: if the host has an IPv6 default route, it adds `net.ipv6.conf.<interface>.accept_dad = 0` to `/etc/sysctl.conf` and applies it. The setting fixes a start error of the service when IPv6 is on.

The server configuration uses these values:

- It listens on `::0` and `0.0.0.0`.
- The method is `chacha20-ietf-poly1305`.
- The mode is `tcp_and_udp`, and `fast_open` is on.
- The plugin is `obfs-server` with `obfs=http`.

## Notes

If `/etc/shadowsocks-libev/config.json` already exists, the script keeps it. In that case, it ignores `--port`, `--password`, `--obfs-host` and `--dns-server`. To apply new values, edit the file and restart the service.

If the GitHub API does not respond, the script has no fallback version for libsodium or mbedTLS. The install then stops with `libsodium version is not specified`. To prevent this, give `--libsodium-version` and `--mbedtls-version`.

To change the obfs host later, run `im -usoh <host>`.
