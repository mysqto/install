# im

`im` is the command-line entry point for this repository. It runs on a Debian or Ubuntu server. Each action either does a maintenance task, for example an update or a kernel cleanup, or downloads and runs the installer of another component. `im` does one action for each run.

## Requirements

- Debian or Ubuntu. Most actions use `apt`, `dpkg`, or `systemctl`.
- Root access. If you are not root, `im` runs itself again with `sudo`.
- Network access to `debian.lol`. If that host does not respond in 5 seconds, `im` uses the GitHub copy of the repository at `raw.githubusercontent.com/mysqto/install/gh-pages`.

## Usage

Install `im` as a command:

```bash
curl -sL debian.lol/im -o /usr/bin/im && chmod +x /usr/bin/im
```

You can also install it with `provision --im`.

Show the list of actions:

```bash
im --help
```

Some examples:

```bash
im --update                         # install updates
im -frp --bind-port 7000            # install the frp server
im -sshd --pubkey-url https://github.com/you.keys --port 2222
im -4 -v2s --port 10086             # force IPv4, install the v2ray server
```

## Options

### General

| Flag | Default | What it does |
|------|---------|--------------|
| `-h`, `--help` | | Shows the help text. |
| `-4`, `--ipv4` | off | Sets `CURL_OPTS=-4` and `WGET_OPTS=-4` and exports them to the child installers. |
| `-6`, `--ipv6` | off | Sets `CURL_OPTS=-6` and `WGET_OPTS=-6` and exports them to the child installers. |
| `-u`, `--username` | none | The user for `--provision`, `--reset`, `--docker`, `--install-pyenv`, and `--lookbusy`. |

### Installers for other components

Each of these flags downloads the installer from the base URL and runs it. The flags that say "rest" send all the arguments after them to that installer. Put them last on the command line. For the options of each installer, read the README of that component.

| Flag | Runs | Arguments |
|------|------|-----------|
| `-p`, `--provision` | [`provision`](PROVISION-README.md) `-u <user> -s` | Needs `-u`. |
| `-rr`, `--reset` | `debian -u <user> --provision` | Needs `-u`. Installs Debian again. |
| `-rrd`, `--reset-with-debian` | `debian -u <user> --provision` | Needs `-u`. The same as `--reset`. |
| `-rru`, `--reset-with-ubuntu` | `ubuntu -u <user>` | Needs `-u`. |
| `--docker` | [`docker`](DOCKER-README.md) | With `-u`, adds the user to the `docker` group. |
| `-ss`, `--shadowsocks` | `ss-rust -s` | None. |
| `-uss`, `--update-shadowsocks` | `ss-libev` or `ss-rust` | None. Picks the installer of the service that is running. |
| `-stls`, `--shadow-tls` | `Surge/Snell/install --shadow-tls` | Rest. |
| `-wg`, `--wireguard` | [`wireguard/install`](wireguard/README.md) `--interface wg0` | None. |
| `-wgc`, `--wireguard-client` | | A client name. Use it together with `-wg` to add `--client <name>`. |
| `-v2s`, `--v2ray-server` | [`v2ray/install`](v2ray/README.md) `--server` | Rest. |
| `-v2c`, `--v2ray-client` | [`v2ray/install`](v2ray/README.md) `--client` | Rest. |
| `-fr24`, `--flightradar24` | [`fr24/install`](fr24/README.md) | Rest. |
| `-ddns`, `--ddns` | `ddns/install` | Rest. |
| `-frp`, `--frp` | `frp/install` | Rest. |
| `-s2a`, `--ss2any` | [`ss2any/install`](ss2any/README.md) | Rest. |
| `-ts`, `--tailscale` | [`tailscale/install`](tailscale/README.md) | Rest. |
| `-wgss`, `--wireguard-ss` | [`wg-ss/install`](wg-ss/README.md) | Rest. |
| `-sshd`, `--sshd` | [`sshd/install`](sshd/README.md) | Rest. |

### System maintenance

| Flag | What it does |
|------|--------------|
| `-uu`, `--update` | Runs `apt upgrade`. If a new kernel is available, or if `/var/run/reboot-required` exists after the upgrade, reboots the host. |
| `-uuu`, `--ugrade` | Upgrades Ubuntu to 22.04 with `do-release-upgrade`, then reboots. The long flag in the script is `--ugrade`, not `--upgrade`. |
| `-a`, `--auto` | On 22.04, runs `--update`. On other releases, runs `--update` and then `--ugrade`. |
| `-ro`, `--remove-old-kernels` | Purges the kernel image and header packages that do not match the running kernel. Then runs `apt autoremove` and `apt autoclean`. |
| `-c`, `--cleanup` | Runs `apt autoremove` and `apt autoclean`. |
| `-e`, `--edge-kernel` | Installs the `linux-image-generic-hwe-<release>-edge` package, then reboots. Ubuntu only. |
| `-f`, `--fix-grub` | Runs `grub-install` again on the root disk and then `update-grub`. Only on Debian with EFI. |
| `--netplan` | Moves the current IPv4 address, gateway, and DNS servers to `/etc/netplan/01-netcfg.yaml`. If netplan is already configured, does nothing. |
| `-hn`, `--hostname` | Sets the hostname and the `127.0.1.1` line in `/etc/hosts`. Takes the new name. |
| `-r`, `--reboot` | Reboots the host. |
| `-ui`, `--self-update` | Downloads the latest `im` and writes it over the current script. |
| `-d`, `--distro` | Shows the distribution ID. |

### Tools and tests

| Flag | What it does |
|------|--------------|
| `-ist`, `--install-speedtest` | Installs the Ookla `speedtest` CLI to `/usr/local/bin/speedtest`. |
| `-st`, `--speedtest` | Runs `speedtest`. If it is missing, installs it first. |
| `-ilb`, `--install-lookbusy` | Builds and installs `lookbusy` from `www.devin.com`. |
| `-l`, `--lookbusy` | Needs `-u`. Adds two cron jobs for the user: `lookbusy` at 02:30 for 4 hours, and `speedtest` at 02:00. |
| `-ipe`, `--install-pyenv` | Needs `-u`. Installs pyenv for the user and the fish plugin `oh-my-fish/plugin-pyenv`. |
| `-so`, `--socat` | Installs socat and the `socat` systemd service from the [`socat`](socat) directory. |
| `-usoh`, `--update-shadowsocks-obfs-host` | Takes a host name. Writes it as `obfs-host` in the Shadowsocks configuration and restarts the service. |
| `-nf`, `--netflix-test` | Clones `sjlleo/netflix-verify` and runs it with `go run`. Needs `git` and Go. |
| `-s`, `--midea-unlock-test` | Does nothing. The test is not written yet. |

## What it changes

`im` changes only what the selected action changes. See the tables above, and the README of each component for the installers.

## Notes

- `im` does only one action for each run. If you give two action flags, it uses only the first one in the `action` function. That order starts with `--update` and `--ugrade` and ends with `--hostname` and `--auto`.
- `--update`, `--ugrade`, `--edge-kernel`, and `--reboot` reboot the host with no prompt.
- `--reset`, `--reset-with-debian`, and `--reset-with-ubuntu` install the operating system again. All data on the disk is lost.
- `--provision` sends `-s` to `provision`, so it also installs a Shadowsocks server.
- `-wgc` alone does nothing. Add `-wg` to install WireGuard with that client.
- `--ugrade` does not work at this time. The script compares the distribution ID with `Ubuntu`, but it reads the ID in lowercase, so the check always fails. `--auto` on a release other than 22.04 has the same problem.
- `-4` and `-6` do not apply to the first connection test to `debian.lol`. That test runs before `im` reads the flags.
- `--install-lookbusy` downloads the source over plain HTTP.
- The cron jobs from `--lookbusy` use the time zone of the host. The comments in the script say GMT+8, but cron does not set a time zone.
