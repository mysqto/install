# frp

`frp/install` installs [frp](https://github.com/fatedier/frp), a reverse proxy that exposes ports on a host behind NAT through a public server. The server side is `frps`. The client side is `frpc`, and it runs on the host behind NAT. The script downloads the frp release from GitHub, writes a TOML configuration, and registers a service. It runs on Linux with systemd and on macOS with launchd.

## Requirements

- Linux or macOS, on `amd64`, `arm64`, `386`, or `arm`.
- Root access on Linux in all modes.
- Root access on macOS for server mode. On macOS without `sudo`, the client modes run in user mode. See [macOS user mode](#macos-user-mode).
- For `--client`: SSH access from the client host to the server.
- For `--ssh-pass`: Linux. The script installs `sshpass` for it. macOS does not support `--ssh-pass`.

If `curl` is missing, the script installs it with `apt-get`, `dnf`, `yum`, `zypper`, `pacman`, or `apk`.

## Usage

The script has five modes. The default mode installs the server.

Download the installer:

```bash
curl -sL debian.lol/frp/install -o frp-install && chmod +x frp-install
```

### Install the server

Run this on the public server:

```bash
sudo ./frp-install
sudo ./frp-install --bind-port 7000 --dashboard-port 7500
```

The script prints the auth token at the end. If `frps.toml` exists and you do not give `--token`, the script keeps the token from that file.

### Install the client over SSH

Run this on the host behind NAT. The script connects to the server over SSH and reads `bindPort` and the token from the `frps` configuration there:

```bash
sudo ./frp-install --client user@frp-server.example.com --proxy ssh:tcp::22:6022
```

The script looks for the server configuration in this order:

1. `<config-dir>/frps.toml`
2. `<config-dir>/frps.ini`
3. `/etc/frp/frps.toml`
4. `/etc/frp/frps.ini`
5. `/usr/local/etc/frp/frps.toml`

### Generate a client configuration on the server

If the client host cannot connect to the server over SSH, use this mode. Run it on the server, after you install `frps`:

```bash
sudo ./frp-install --gen-client /tmp/frpc.toml --proxy ssh:tcp::22:6022
```

The script writes a complete `frpc.toml` to the path. It does not install anything. If you do not give `--server-addr`, the script detects the public IP address of the server. If that fails, it uses the hostname.

### Install the client from a configuration file

Copy the generated file to the client host. Then install `frpc` with it:

```bash
scp /tmp/frpc.toml user@nat-box:~/frpc.toml
ssh user@nat-box 'sudo bash -c "$(curl -sL https://debian.lol/frp/install)" -- --from-config ~/frpc.toml'
```

### Add a proxy to an installed client

Run this on the client host. The script adds the proxy to `<config-dir>/frpc.toml` and restarts the service. It does not change the binary, the service file, or the server address and token:

```bash
sudo ./frp-install --add-proxy web:http:127.0.0.1:8080:0
```

If a proxy with the same name exists, the script replaces it.

### Proxy specification

`--proxy` and `--add-proxy` take `NAME:TYPE:LIP:LPORT:RPORT`:

- `NAME`: the proxy name. The script adds the client name as a prefix, for example `myhost-ssh`.
- `TYPE`: the frp proxy type, for example `tcp` or `http`.
- `LIP`: the local IP address. If it is empty, the script uses `127.0.0.1`.
- `LPORT`: the local port.
- `RPORT`: the remote port on the server.

You can repeat both flags. If you give no `--proxy`, the script writes a commented example to the configuration.

For each `tcp` proxy with local port 22, the script prints a `~/.ssh/config` snippet that connects to the client through the server.

### Through im

`im -frp` sends all arguments after `-frp` to `frp/install`:

```bash
im -frp --client user@frp-server.example.com --proxy ssh:tcp::22:6022
```

## Options

### Server mode

| Flag | Default | What it does |
|------|---------|--------------|
| `--bind-port` | `7000` | Port that `frps` listens on for clients |
| `--token` | generated, or kept from `frps.toml` | Auth token |
| `--dashboard-port` | off | Turns on the dashboard on this port, on `0.0.0.0` |
| `--dashboard-user` | `admin` | Dashboard user |
| `--dashboard-pwd` | generated | Dashboard password |

### Client modes

| Flag | Default | What it does |
|------|---------|--------------|
| `--client` | | Client mode. The value is the SSH target, `user@host` or `host` |
| `--ssh-port` | `22` | SSH port |
| `--ssh-key` | | SSH private key |
| `--ssh-pass` | `FRP_SSH_PASS` env var | SSH password. Linux only |
| `--server-addr` | host part of `--client`, or the detected public IP for `--gen-client` | Server address in `frpc.toml` |
| `--name` | `hostname -s`, or `client` for `--gen-client` | Prefix for proxy names |
| `--proxy` | | Adds a proxy. Repeatable |
| `--gen-client` | | Gen-client mode. The value is the output path |
| `--from-config` | | Installs the client from a file. The value is the path to `frpc.toml` |
| `--add-proxy` | | Add-proxy mode. The value is a proxy specification. Repeatable |

### All modes

| Flag | Default | What it does |
|------|---------|--------------|
| `--prefix` | `/usr/local` as root, `$HOME/.local` in user mode | Install prefix. The binary goes in `<prefix>/bin` |
| `--config-dir` | `/etc/frp` as root, `$HOME/.config/frp` in user mode | Configuration directory. In client mode, also the first path that the script reads on the server |
| `--version` | latest release | frp version to install, for example `0.62.1` |
| `-4`, `--ipv4` | | Forces IPv4 for downloads |
| `-6`, `--ipv6` | | Forces IPv6 for downloads |
| `-h`, `--help` | | Shows the help text |

If the installed binary already has the requested version, the script does not download it again.

## What it changes

- `<prefix>/bin/frps` or `<prefix>/bin/frpc`: the binary.
- `<config-dir>/frps.toml` or `<config-dir>/frpc.toml`: the configuration, mode `644`.
- On Linux with systemd: `/etc/systemd/system/frps.service` or `frpc.service`. The service runs with `DynamicUser=true` and `CAP_NET_BIND_SERVICE`. Read its log with `journalctl -u frps` or `journalctl -u frpc`.
- On macOS as root: `/Library/LaunchDaemons/com.fatedier.<name>.plist`, in the `system` domain. It runs as `$SUDO_USER`. If `SUDO_USER` is not set, it runs as `nobody`. The log is `/var/log/<name>.log`.
- On macOS in user mode: `~/Library/LaunchAgents/com.fatedier.frpc.plist`, in the `user/<uid>` domain. The log is `~/Library/Logs/frpc.log`.

`<name>` is `frps` or `frpc`. On Linux without systemd, the script does not install a service. It prints the command that starts the binary.

## macOS user mode

On macOS, a client mode that you run without `sudo` installs `frpc` for the current user only. Server mode on macOS needs `sudo`.

In user mode, the script writes a LaunchAgent with `LimitLoadToSessionType` set to `Background`. Then it does these steps:

1. It removes any old registration of `com.fatedier.frpc` from the `system`, `gui/<uid>`, and `user/<uid>` domains.
2. It runs `launchctl bootstrap user/<uid>` with the plist.
3. It enables and kickstarts the job.
4. It runs `launchctl list com.fatedier.frpc` to make sure that the job is loaded.

These steps work from an SSH session and from Terminal. The LaunchAgent does not start at boot. At the next login of the user, it loads again. To make `frpc` start at boot, run the script with `sudo` to install a LaunchDaemon.

`--add-proxy` in user mode restarts the job with `launchctl kickstart -k user/<uid>/com.fatedier.frpc`. If the job is not loaded, it bootstraps the plist.

### If the LaunchAgent does not load

The script prints `LaunchAgent did not load` and the error from `launchctl bootstrap`. Load the job by hand:

1. Remove a system registration that holds the label:

   ```bash
   sudo launchctl bootout system/com.fatedier.frpc 2>/dev/null
   ```

2. Bootstrap the LaunchAgent in your user domain:

   ```bash
   launchctl bootstrap user/$(id -u) ~/Library/LaunchAgents/com.fatedier.frpc.plist
   ```

3. Make sure that the job is loaded:

   ```bash
   launchctl list com.fatedier.frpc
   ```

Do not use `launchctl load -w` for this. That command can print `Load failed: 5: Input/output error` and still exit with status 0.

## Notes

- Keep the configuration files private. `frps.toml` and `frpc.toml` hold the auth token, and `frps.toml` can hold the dashboard password. The script sets mode `644`, so all local users can read them.
- The script prints the token and the dashboard password to the terminal. If other people can read your terminal history or logs, clear them.
- The dashboard listens on `0.0.0.0`. If you turn it on, limit access to the dashboard port with a firewall. The script does not change firewall rules.
- The script does not open `--bind-port` or the remote proxy ports in a firewall. Open them on the server yourself.
- `--client` connects with `StrictHostKeyChecking=accept-new`. On the first connection, the script accepts the server host key without a prompt.
- On Linux, all modes need root, including `--gen-client`.
- The script has no uninstall mode.
