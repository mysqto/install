# ubuntu

`ubuntu` reinstalls a running Linux host with Ubuntu 20.04 LTS (focal). It works like [debian](DEBIAN-README.md). The script downloads the Ubuntu netboot installer from the `focal-proposed` archive. It builds a preseed file (a file of answers for the installer) from the current host. It adds a GRUB entry for the installer and reboots into it. The installer then erases the disk and installs Ubuntu with no questions. The script installs only Ubuntu 20.04. It has no flag to choose another release.

## Requirements

- A host that uses `apt`. The script installs `systemd`, `pwgen`, `whois`, `curl`, `cpio`, `openssh-client` and `jq` with `apt`.
- An `amd64` or `arm64` CPU. For another architecture, the script stops.
- A host that boots with GRUB. The script needs `grub-mkconfig` or `grub2-mkconfig`, and `grub-reboot` or `grub2-reboot`.
- Root. If you are not root, the script runs itself again with `sudo`.
- The `ip` command from iproute2.
- Internet access to `https://debian.lol` or `https://raw.githubusercontent.com`.

## Usage

Download the script on the host that you want to reinstall:

```bash
curl -sL debian.lol/ubuntu -o ubuntu && chmod +x ubuntu
```

Write the installer files and the GRUB menu without a reboot:

```bash
./ubuntu --dry-run --user new_user_name --authorized-keys-url your_authorized_keys_url_here
```

Reinstall the host. The host reboots 3 seconds after the script finishes:

```bash
./ubuntu --user new_user_name \
         --password your_password_here \
         --authorized-keys-url your_authorized_keys_url_here \
         --hostname some_hostname
```

## Options

The script has no `--help` flag. `-h` sets the hostname. For an unknown flag, the script prints a warning and continues.

### Account and SSH

| Flag | Default | What it does |
|------|---------|--------------|
| `-u`, `--user NAME` | 8 random characters | Name of the user that the installer creates. Root login is off. |
| `-f`, `--fullname NAME` | Full name of that user on the current host, else the user name | Full name of the new user. |
| `-uid`, `--uid UID` | UID of that user on the current host, else 4 random digits | UID of the new user. |
| `-p`, `--password PASS` | Password hash of that user on the current host, else 32 random characters | Password of the new user. |
| `-ak`, `--authorized-keys KEYS` | | SSH public keys. `provision` uses them. |
| `-aku`, `--authorized-keys-url URL` | | URL to download SSH public keys from. The network console also uses this URL. |
| `--ssh`, `--ssh-port PORT` | `Port` in `/etc/ssh/sshd_config`, else `22` | SSH port that `provision` sets. |
| `--sudo-without-password` | Off | `provision` gives the user `sudo` with no password. |

If you give no keys, the script uses `/home/<user>/.ssh/authorized_keys` on the current host. If that file is missing, the script makes a new 4096-bit RSA key pair and prints the private key.

### Disk and boot

| Flag | Default | What it does |
|------|---------|--------------|
| `-m`, `--manual-partition` | Off | Uses the partition layout from the flags below. Without it, the installer uses all of the first disk for one partition. |
| `-d`, `--disk DEV` | Disk that holds `/` | Disk to install to. Only with `--manual-partition`. |
| `-fs`, `--filesystem FS` | `ext4` | File system for `/`. Only with `--manual-partition`. |
| `-e`, `--efi` | On if `/sys/firmware/efi` exists | Makes an EFI system partition. Only with `--manual-partition`. |
| `-esp`, `--esp-size MB` | `128` | Size of the EFI system partition. Only with `--manual-partition`. |
| `-bs`, `--boot-size MB` | `512` | Size of the `/boot` partition. Only with `--manual-partition`. |
| `-g`, `--gpt` | Off, on with EFI | GPT partition table. Only with `--manual-partition`. |
| `-k`, `--kernel PKG` | | Kernel package for the installer to install. |
| `-c`, `--cloud NAME` | | Uses the `<NAME>.archive.ubuntu.com` mirror, or `<NAME>.ports.ubuntu.com` on `arm64`. |

### Network

| Flag | Default | What it does |
|------|---------|--------------|
| `-i`, `--interface IFACE` | `auto` | Interface for the installer. |
| `-s`, `--static-ip` | Off | Turns off DHCP in the installer and uses the current address. |
| `-ip`, `--ip-address IP` | Current IPv4 address | Address for the installer. |
| `-nm`, `--netmask MASK` | Current netmask | Netmask for the installer. |
| `-gw`, `--gateway IP` | Current IPv4 default gateway | Gateway for the installer. |
| `-dns`, `--dns "S1 S2"` | Current DNS, else `1.1.1.1` | Name servers for the installer. |
| `-h`, `--hostname NAME` | Current hostname | Hostname of the new system. |
| `-t`, `--timezone TZ` | Current time zone, else `UTC` | Time zone. |
| `-n`, `--ntp-server HOST` | `time.cloudflare.com` | NTP server. |
| `-ns`, `--network-console` | Off | Starts an SSH server in the installer so that you can watch the install. |
| `-4`, `--ipv4` | Off | Forces `curl` and `wget` in the script to use IPv4. |
| `-6`, `--ipv6` | Off | Forces `curl` and `wget` in the script to use IPv6. |
| `--dry-run` | Off | Does not reboot. See the notes. |

### Post-install steps

These flags run the `provision` script inside the new system at the end of the install.

| Flag | What it does |
|------|--------------|
| `--provision` | Enables `provision` with Shadowsocks, Shadow-TLS, `--go`, `--im`, `--fish`, `--neofetch`, `--backports`, `--bbr` and `--byobu`. |
| `--go`, `--im`, `--fish`, `--neofetch`, `--byobu`, `--socat`, `--backports` | Passes the same flag to `provision`. |
| `-bbr`, `--bbr` | Turns on TCP BBR. |
| `-ss`, `--shadowsocks-libev` | Installs Shadowsocks. |
| `-ssp`, `--shadowsocks-password`, `-sspt`, `--shadowsocks-port`, `-sspobfs`, `--shadowsocks-obfs-host` | Shadowsocks values. Defaults come from `/etc/shadowsocks-libev/config.json`, else random values and `gateway.icloud.com`. |
| `-stls`, `--shadow-tls` | Installs Snell behind Shadow-TLS. |
| `--shadow-tls-port`, `--shadow-tls-password`, `--shadow-tls-obfs` | Shadow-TLS values. Defaults come from `/etc/default/shadow-tls`, else random values and `gateway.icloud.com`. |
| `--snell-port`, `--snell-psk` | Snell values. Defaults come from `/etc/snell/snell-server.conf`, else random values. |

The tool flags, such as `--go`, have an effect only with `--provision`.

## What it changes

On the current host, the script does these steps:

1. It installs the packages that it needs. During the install, it replaces `/etc/apt/apt.conf.d/local` and then puts the original back.
2. It writes `/boot/vmlinuz<timestamp>` and `/boot/initrd.img<timestamp>`. The initrd contains the preseed file.
3. It copies the GRUB file to `grub.cfg.<timestamp>.bak` next to the original.
4. It replaces `/etc/grub.d/40_custom` with one entry, `Install Ubuntu 20.04 LTS`. It makes the entry from a copy of the first entry in the current GRUB menu.
5. It runs `grub-mkconfig` and `grub-reboot` to boot that entry one time.
6. It reboots after 3 seconds.

The installer then erases the disk and installs Ubuntu with a minimal task. It adds `openssh-server`, `net-tools`, `curl`, `wget`, `git`, `tig`, `build-essential`, `software-properties-common` and `vim`. It does not install updates. It creates the user, turns off root login and sets the time zone and NTP server.

## Notes

- Do not run the script on a host with data that you need. The installer erases the disk with no prompt.
- Do not run the script without a plan for console access. If the installer fails, you need the console of your cloud provider to repair the host.
- The script starts at once. It does not ask for confirmation, and it reboots 3 seconds after it finishes.
- `--dry-run` does not reboot. It still installs packages, writes to `/boot`, replaces `/etc/grub.d/40_custom` and rebuilds the real GRUB file one time. The next boot menu can contain the installer entry.
- The preseed file sets `debian-installer/allow_unauthenticated` to `true`. The installer accepts packages with no valid signature.
- If `/etc/apt/sources.list` has a `restricted` line, the installer uses that mirror, and `--cloud` has no effect.
- The script prints the password, the password hash, the generated private key and the proxy passwords to the terminal. Clear the terminal history after the run.
- The script replaces any entries that you had in `/etc/grub.d/40_custom`.
- The `provision` step runs `bash <(curl ...)` inside `sh -c` in the new system. If `sh` is `dash`, that command fails and `provision` does not run. This note comes from a reading of the script, not from a test.
- For a current Debian release, use [debian](DEBIAN-README.md).
