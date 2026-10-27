# ss-rust

`ss-rust` installs the shadowsocks-rust server (`ss-server`) and, by default, the simple-obfs plugin. With `--setup`, it also writes a server configuration and runs the server as a systemd service. Run it on the server, as root.

This script is for the server. To install a client, use `ss-rust-client`, which [SS-CLIENT-README.md](SS-CLIENT-README.md) describes. For the older server that builds shadowsocks-libev from source, see [SS-LIBEV-README.md](SS-LIBEV-README.md).

## Requirements

- Linux on `x86_64`, `aarch64` or `i686`. The script picks the glibc or the musl release automatically.
- Root. The script stops with `Please run as root` for other users.
- systemd, for `--setup` only.
- One of `apt-get`, `yum`, `dnf`, `zypper` or `apk`, for the dependencies. Without one, you must install `git`, `python3` and `pwgen` yourself.
- Outbound access to `api.github.com` and `github.com`.

The script also accepts macOS (`Darwin`) for the binary download. The `--setup` step uses systemd and does not work on macOS.

## Usage

Download the script on the server:

```bash
curl -sL debian.lol/ss-rust -o ss-rust && chmod +x ss-rust
```

Install or update the binaries only. This does not change the configuration or the service:

```bash
sudo ./ss-rust
```

Install the binaries, write the configuration and start the service with random values:

```bash
sudo ./ss-rust --setup
```

Set fixed values:

```bash
sudo ./ss-rust --setup -P 8388 -p 'your-password' -o cdn.example.com
```

Run the server without simple-obfs:

```bash
sudo ./ss-rust --setup --plugin none
```

At the end of `--setup`, the script prints the server values. These include the listen address, the port, the password, the plugin and the obfs host.

You can also run the script through `im`:

- `im -ss` runs `ss-rust --setup`.
- If the `shadowsocks` service is active, `im -uss` runs `ss-rust` without `--setup`. This updates the binaries only.
- `im -usoh <host>` changes the obfs host in the configuration and restarts the service.

## Options

| Flag | Default | What it does |
|------|---------|--------------|
| `-P`, `--port <port>` | Random unused port, 10000 to 65000 | Server port. |
| `-p`, `--password <pw>` | Random, 32 characters | Server password. |
| `-o`, `--obfs-host <host>` | Random from a fixed list | Host name that simple-obfs uses for HTTP obfuscation. |
| `-d`, `--dns-server <ip>` | The two fastest public resolvers | DNS server for the server. |
| `-m`, `--method <method>` | `chacha20-ietf-poly1305` | Cipher. |
| `-n`, `--network <net>` | `tcp_and_udp` | `tcp`, `udp` or `tcp_and_udp`. |
| `-L`, `--listen <addr>` | `0.0.0.0` | Bind address. |
| `-s`, `--setup` | Off | Write the configuration and install or restart the systemd service. |
| `-4`, `--ipv4` | Off | Use IPv4 for downloads. |
| `-6`, `--ipv6` | Off | Use IPv6 for downloads. |
| `--plugin <name>` | `simple-obfs` | `simple-obfs` or `none`. |
| `--force-obfs` | Off | Build simple-obfs again. Without this flag, the script skips the build if `obfs-server` is installed. |
| `--shadowsocks-rust-version <v>` | Latest release | shadowsocks-rust release to install. |
| `-h`, `--help` | | Show the help text. |

The random obfs host is one of `microsoft.com`, `apple.com`, `gateway.icloud.com`, `gateway.messenger.live.com` and `officecdn.microsoft.com.edgesuite.net`.

To select the DNS server, the script pings a list of public resolvers and keeps the two with the lowest latency. If the host has only an IPv6 route, it uses IPv6 resolvers. If no resolver replies, it uses `1.1.1.1`, or `2001:4860:4860::8888` on an IPv6-only host.

An unknown flag prints a warning, and the install continues. The environment variables `CURL_OPTS` and `WGET_OPTS` pass extra flags to `curl` and `wget`.

## What it changes

Without `--setup`:

- Packages: it installs `git`, `pwgen` and `python3`. If it builds simple-obfs, it also installs the build tools for your package manager.
- Binary: it installs `ssserver` from the release as `/usr/local/bin/ss-server`.
- Plugin: it builds simple-obfs from GitHub and installs it under `/usr/local`. If `obfs-server` is already on the `PATH`, it skips this step. `--force-obfs` makes it build the plugin again.

With `--setup`, it also does these steps:

- Configuration: it writes `/etc/shadowsocks/config.json`. If `/etc/shadowsocks-libev/config.json` exists, it writes that file instead.
- Defaults file: it writes `/etc/default/shadowsocks`.
- Service: it writes `/lib/systemd/system/shadowsocks.service`, then enables and restarts `shadowsocks.service`.

The service runs as a dynamic user with only `CAP_NET_BIND_SERVICE`. It restarts on failure after 5 seconds.

## Notes

If a configuration file from an earlier install exists, `--setup` reads the password, the port, the obfs host and the DNS server from it. A flag on the command line replaces the value from the file.

If the port from the earlier configuration is still in use, `--setup` stops with `requested port <port> is already in use`. If the old `shadowsocks` or `shadowsocks-libev` service still runs, this error occurs. Stop that service first, or give a new port with `-P`.

To keep the shadowsocks-libev configuration, do not run `--setup`. The script writes its new configuration over `/etc/shadowsocks-libev/config.json`.

If the service does not start, the script prints a warning and exits with code 1. Read the log with `journalctl -u shadowsocks -e`.
