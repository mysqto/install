# provision

`provision` sets up a new Debian or Ubuntu server. It upgrades the system, installs a base set of packages, and creates and configures a login user. Flags turn on optional parts such as fish, Docker, Go, Shadowsocks, Snell with Shadow-TLS, BBR, and network changes. The `debian` installer and `im --provision` both call this script.

## Requirements

- Debian or Ubuntu. The script stops on any other distribution.
- Root access. If you are not root, the script runs itself again with `sudo`. If `sudo` is missing and you are root, the script installs it.
- Network access to `debian.lol`. If that host does not respond in 5 seconds, the script uses the GitHub copy of the repository at `raw.githubusercontent.com/mysqto/install/gh-pages`.

## Usage

Download the script:

```bash
curl -sL debian.lol/provision -o provision && chmod +x provision
```

To create a user with your SSH key, fish, and Docker, run:

```bash
./provision --user alice \
            --authorized-keys "$(curl -sL https://github.com/alice.keys)" \
            --fish --docker --bbr
```

To also install a Shadowsocks server on a fixed port, add these flags:

```bash
./provision --user alice --shadowsocks --shadowsocks-port 8388
```

## Options

The script has no `--help` flag. `-h` sets the hostname.

### Base system and user

| Flag | Default | What it does |
|------|---------|--------------|
| `-u`, `--user`, `--username` | none | Creates this user and configures its sudo rules. Without it, the script does not create or change a user. |
| `-ak`, `--authorized-keys` | none | Public SSH keys for the user. Needs `--user`. |
| `-akb`, `--authorized-keys-base64` | none | The same as `--authorized-keys`, but the value is base64 text. |
| `--sudo-without-password` | off | Gives the user `NOPASSWD: ALL` in sudo. |
| `-h`, `--hostname` | none | Sets the hostname. |
| `--ssh`, `--ssh-port` | none | Sets `Port` in `/etc/ssh/sshd_config` and restarts `sshd`. |
| `--force-ipv4` | off | Sets `CURL_OPTS=-4` for the downloads of this script. |
| `--force-ipv6` | off | Sets `CURL_OPTS=-6` for the downloads of this script. |

### Software

| Flag | Default | What it does |
|------|---------|--------------|
| `-f`, `--fish` | off | Installs fish, makes it the shell of the user, and installs fisher with the `jethrokuan/z` and `mysqto/flash` plugins. |
| `-nf`, `--neofetch` | off | Builds and installs neofetch from GitHub. |
| `-g`, `--go` | off | Runs the [`go`](GO-README.md) installer. |
| `-im`, `--im` | off | Downloads [`im`](IM-README.md) to `/usr/bin/im`. |
| `-d`, `--docker` | off | Runs the [`docker`](DOCKER-README.md) installer and adds the user to the `docker` group. |
| `--byobu`, `--enable-byobu` | off | Runs `byobu-enable` for the user. Needs `--user`. |
| `-so`, `--socat` | off | Installs socat and the `socat` systemd service from the [`socat`](socat) directory. |
| `-qa`, `--qemu-guest-agent` | off | Installs `qemu-guest-agent`. |

### Shadowsocks

| Flag | Default | What it does |
|------|---------|--------------|
| `-s`, `--shadowsocks` | off | Runs the [`ss-rust`](ss-rust) installer with `--setup`. |
| `-ssp`, `--shadowsocks-password` | see below | The Shadowsocks password. |
| `-ssP`, `--shadowsocks-port` | see below | The Shadowsocks port. |
| `--shadowsocks-obfs-host` | see below | The obfs host name. |

For each Shadowsocks value that you do not give, the script reads it from the existing configuration file. If `/etc/shadowsocks-libev/config.json` exists, it uses that file. If not, it uses `/etc/shadowsocks/config.json`. If the file does not have the value, the script uses these defaults:

- Password: a random 32-character string.
- Port: a random port from 10000 to 65535 that is not the SSH port.
- Obfs host: `gateway.icloud.com`.

### Snell and Shadow-TLS

| Flag | Default | What it does |
|------|---------|--------------|
| `-stls`, `--shadow-tls` | off | Runs the [`Surge/Snell/install`](Surge/Snell/install) installer with Shadow-TLS. |
| `--snell-port` | see below | The Snell port. |
| `--snell-psk` | see below | The Snell pre-shared key. |
| `--snell-version` | `4` | The Snell version. |
| `--snell-obfs`, `--shadow-tls-obfs` | `tls` | The Snell obfs mode. |
| `--shadow-tls-port` | see below | The Shadow-TLS port. |
| `--shadow-tls-password` | see below | The Shadow-TLS password. |
| `--shadow-tls-obfs-host` | see below | The host name that Shadow-TLS uses for its TLS handshake. |

For each value that you do not give, the script reads it from `/etc/snell/snell-server.conf` or `/etc/default/shadow-tls`. If those files do not have the value, the script uses these defaults:

- Ports: a random port from 10000 to 65535 that is not used by SSH, Shadowsocks, or the other Snell port.
- PSK and password: a random 32-character string.
- Obfs host: one of `microsoft.com`, `apple.com`, or `gateway.icloud.com`, at random.

### Network and boot

| Flag | Default | What it does |
|------|---------|--------------|
| `-bbr`, `--bbr` | off | Adds `fq` and `bbr` to `/etc/sysctl.conf` and loads them. |
| `-6`, `--ipv6-dhcp` | off | Adds `iface <interface> inet6 dhcp` to `/etc/network/interfaces`. |
| `-d6`, `--disable-ipv6` | off | Sets `ipv6.disable=1` on the kernel command line. Turns off `--ipv6-dhcp`. |
| `--ethx` | off | Adds `net.ifnames=0 biosdevname=0` to the kernel command line, so the interface names become `eth0` and so on after a reboot. |
| `--netplan` | off | Installs `netplan.io` and moves the current IPv4 address, gateway, and DNS servers to `/etc/netplan/01-netcfg.yaml`. |

## What it changes

The script always does these steps:

1. Runs `apt update` and `apt upgrade -y`.
2. Installs `byobu`, `wget`, `curl`, `net-tools`, `build-essential`, `git`, `vim`, `tig`, `jq`, `dnsutils`, and `pwgen`.

With `--user`, the script also does these steps:

1. If the user does not exist, creates the user and a group with the same name. The first free ID from 1024 becomes the UID and the GID. The user is in the `sudo` group. If fish is installed, the shell is fish. If not, the shell is bash.
2. With `--authorized-keys`, writes the keys to `~/.ssh/authorized_keys`. It sets `PasswordAuthentication no` in `/etc/ssh/sshd_config`. If the user is not `root`, it also sets `PermitRootLogin no`.
3. Writes `/etc/sudoers.d/<user>`. Without `--sudo-without-password`, the user can run only a fixed list of commands without a password. The list includes `apt`, `dpkg`, `systemctl`, `reboot`, `curl`, `wget`, `zsh`, `fish`, and `busybox`. With `--im`, it also includes `/usr/bin/im`.

The script does not set a password for the new user.

Other files that the flags change:

- `/etc/hostname` and `/etc/hosts`, with `--hostname`. The script writes them only when `hostnamectl` fails.
- `/etc/default/grub`, with `--disable-ipv6` or `--ethx`.
- `/etc/apt/sources.list.d/shells:fish:release:3.list` on Debian, or the `fish-shell/release-3` PPA on Ubuntu, with `--fish`.
- `/lib/systemd/system/socat.service`, `/etc/socat`, and `/etc/socatrc`, with `--socat`.

## Notes

- If you give `--authorized-keys`, the script deletes the existing `~/.ssh` directory of the user first. All files in it are lost, not only `authorized_keys`.
- Do not use `--sudo-without-password` on a shared host. The user gets root access with no password.
- The default sudo rules also give passwordless access to `zsh`, `fish`, `busybox`, `curl`, and `wget`. A user can use these commands to get a root shell. Treat the default as root access without a password.
- If you use `--disable-ipv6`, the script replaces the whole kernel command line in `GRUB_CMDLINE_LINUX_DEFAULT`. Other values there are lost.
- If you use `--netplan`, the script deletes all files in `/etc/netplan/*.yaml` and removes all non-loopback entries from `/etc/network/interfaces`. Make sure that you have console access before you reboot.
- Reboot the host to apply `--disable-ipv6`, `--ethx`, and `--netplan`. The script does not reboot.
- The script always exits with status 0, also after an error. This keeps a Debian preseed install from failing. Read the output to find errors.
- `--force-ipv4` and `--force-ipv6` do not apply to the child installers for Go, Shadowsocks, Snell, and Docker. To force them too, set `CURL_OPTS` in the environment.
