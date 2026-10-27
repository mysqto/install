# debian

`debian` reinstalls a running Linux host with an official Debian release. It works on most cloud servers, for example Oracle Cloud, Linode and Digital Ocean. The script downloads the Debian netboot installer and builds a preseed file (a file of answers for the Debian installer) from the current host. It adds a GRUB entry for the installer and reboots into it. The installer then erases the disk and installs Debian with no questions.

## Requirements

- A Linux host that boots with GRUB. The script needs `grub-mkconfig` or `grub2-mkconfig`, `grub-mkrelpath` or `grub2-mkrelpath`, and `grub-reboot` or `grub2-reboot`.
- Root. If you are not root, the script runs itself again with `sudo`.
- One of the `apt-get`, `yum` or `apk` package managers. The script uses it to install `curl`, `jq`, `cpio`, `xz` tools, `pwgen` and `openssh-client` on the current host.
- The `ip` command from iproute2.
- Internet access to `https://debian.lol`. If that host does not answer, the script uses GitHub through the `ghp.ci` proxy.
- An architecture that Debian supports: `amd64`, `arm64`, `i386` or `ppc64el`. The script finds it with `dpkg --print-architecture` or `uname -m`.

## Usage

Download the script on the host that you want to reinstall:

```bash
curl -sL debian.lol/debian -o debian && chmod +x debian
```

Write the installer files and the GRUB menu without a reboot. Read the printed preseed file before you continue:

```bash
./debian --dry-run --user new_user_name --authorized-keys-url your_authorized_keys_url_here
```

Reinstall the host. The host reboots 3 seconds after the script finishes:

```bash
./debian --user new_user_name \
         --uid 1024 \
         --password your_password_here \
         --authorized-keys-url your_authorized_keys_url_here \
         --cloud \
         --efi \
         --hostname some_hostname
```

Reinstall and run the post-install steps:

```bash
./debian --user new_user_name --authorized-keys-url your_authorized_keys_url_here --minimal
./debian --user new_user_name --authorized-keys-url your_authorized_keys_url_here --tiny
```

`--minimal` runs the `provision` script after the install with a small set of features. `--tiny` also runs [tiny](TINY-README.md) after `provision`. With `--tiny`, the new system uses about 38 MB of RAM and 275 MB of disk.

After the reboot, the install runs with no input. If the network console is on, you can connect to the installer over SSH with the network console password that the script prints.

## Options

The script has no `--help` flag. `-h` sets the hostname. For an unknown flag, the script prints a warning and continues.

### Release and mirror

| Flag | Default | What it does |
|------|---------|--------------|
| `-v`, `--version VER` | `stable` | Debian release. Use `11`, `bullseye` or `oldoldstable`. Use `12`, `bookworm` or `oldstable`. Use `13`, `trixie` or `stable`. Use `14`, `forky` or `testing`. Use `sid` or `unstable`. |
| `--sid`, `--unstable` | | Same as `--version sid`. |
| `-a`, `--architecture ARCH` | Found from the host | Debian architecture, for example `amd64`. |
| `--daily` | On for `testing` and `sid` | Uses the daily installer images from `d-i.debian.org`. |
| `--cdn` | | Uses `https://deb.debian.org`. The security repository comes from the same mirror. |
| `--aws` | | Uses `cdn-aws.deb.debian.org` and the NTP server `time.aws.com`. |
| `--aliyun` | | Uses `mirrors.aliyun.com`, Aliyun DNS and `ntp.aliyun.com`. |
| `--ustc`, `--china` | | Uses `mirrors.ustc.edu.cn`, DNS `119.29.29.29` and `time.amazonaws.cn`. |
| `--tuna` | | Uses `mirrors.tuna.tsinghua.edu.cn`, DNS `119.29.29.29` and `time.amazonaws.cn`. |
| `--cloudflare` | | Uses Cloudflare DNS and `time.cloudflare.com`. It does not change the mirror. |
| `-mp`, `--mirror-protocol P` | `https` | `http`, `https` or `ftp`. |
| `-mh`, `--mirror-host HOST` | `deb.debian.org` | Mirror host. |
| `-md`, `--mirror-directory DIR` | `/debian` | Mirror path. |
| `-sr`, `--security-repository URL` | `http://security.debian.org/debian-security` | Security repository. The value `mirror` uses the main mirror. |
| `--backports` | Off | Adds the backports repository and prefers the backports kernel. |
| `-c`, `--cloud`, `--cloud-kernel` | Off | Installs the `linux-image-cloud-*` kernel. |
| `--firmware` | Off | Adds the non-free firmware archive to the installer. |
| `--upgrade TYPE` | `safe-upgrade` | `none`, `safe-upgrade` or `full-upgrade` during the install. |

### Account and SSH

| Flag | Default | What it does |
|------|---------|--------------|
| `-u`, `--user NAME` | 8 random characters | Name of the user that the installer creates. Root login is off. |
| `-uid`, `--uid UID` | UID of that user on the current host, else 4 random digits | UID of the new user. |
| `-p`, `--password PASS` | Password hash of that user on the current host, else 32 random characters | Password of the new user. |
| `-ak`, `--authorized-keys KEYS` | | SSH public keys for the new user. |
| `-aku`, `--authorized-keys-url URL` | | URL to download SSH public keys from. |
| `--ssh`, `--ssh-port PORT` | `Port` in `/etc/ssh/sshd_config`, else `22` | SSH port that `provision` sets. |
| `--sudo-without-password` | Off | `provision` gives the user `sudo` with no password. |

If you give no keys, the script uses `/home/<user>/.ssh/authorized_keys` on the current host. If that file is missing, the script makes a new 4096-bit RSA key pair and prints the private key.

### Disk and boot

| Flag | Default | What it does |
|------|---------|--------------|
| `-d`, `--disk DEV` | Disk that holds `/` | Disk to install to. With `--lvm` or `--jbod`, give a comma-separated list. |
| `--lvm` | Off | Puts `/` on LVM (volume group `vg0`) across the disks. With no `--disk`, it uses all disks. |
| `--jbod` | Off | Puts `/` on one RAID 0 array across the disks. With no `--disk`, it uses all disks. You cannot use it with `--lvm`. |
| `-f`, `--filesystem FS` | `ext4` | File system for `/`. |
| `-e`, `--efi` | On if `/sys/firmware/efi` exists | Makes an EFI system partition. On a host with no EFI, the script ignores it. |
| `-esp`, `--esp-size MB` | Size of the current EFI partition, else `128` | Size of the EFI system partition. |
| `-boot`, `--boot-size MB` | Size of the current `/boot`, at least `512` | Size of the `/boot` partition. |
| `-g`, `--gpt` | On | GPT partition table. It is always on. |
| `--grub-config FILE` | First `grub.cfg` under `/boot` | GRUB file to update. |
| `--force-efi-extra-removable` | Off | Also installs GRUB to the removable EFI path. |
| `--force-lowmem LEVEL` | `1` with 512 MB of RAM or less, else `0` | Low-memory level of the installer: `0`, `1` or `2`. |

### Network

| Flag | Default | What it does |
|------|---------|--------------|
| `-i`, `--interface IFACE` | `auto` | Interface for the installer. |
| `-s`, `--static-ip` | Off | Turns off DHCP in the installer and uses the current address. |
| `-ip`, `--ip-address IP` | Current address | Address for the installer. |
| `-nm`, `--netmask MASK` | Current netmask | Netmask for the installer. |
| `-gw`, `--gateway IP` | Current default gateway | Gateway for the installer. |
| `-dns`, `--dns "S1 S2"` | Current DNS, else the 2 fastest public resolvers | Name servers for the installer. |
| `-6`, `--ipv6`, `--ipv6-only` | On if the host has no IPv4 route | Uses IPv6 for the installer network. |
| `-d6`, `--disable-ipv6` | Off | `provision` turns off IPv6. |
| `--ethx` | Off | Uses `eth0` style interface names (`net.ifnames=0 biosdevname=0`). |
| `--netplan` | Off | `provision` uses netplan. |
| `-4`, `--ipv4` | Off | Forces `curl` and `wget` in the script to use IPv4. |
| `-h`, `--hostname NAME` | Current hostname | Hostname of the new system. |
| `-t`, `--timezone TZ` | Time zone from IP geolocation, else the current time zone, else `UTC` | Time zone. |
| `-n`, `--ntp-server HOST` | `time.cloudflare.com` | NTP server. |
| `-ns`, `--network-console` | Off | Starts an SSH server in the installer so that you can watch the install. |
| `-nck`, `--network-console-authorized-key-url URL` | | Key URL for the network console. If the download fails, the script uses a password. |

If the gateway is not in the subnet of the address, the script adds a host route in the installer.

### Post-install steps

These flags run the `provision` script inside the new system at the end of the install. The `provision` script installs and sets up the tools.

| Flag | What it does |
|------|--------------|
| `--provision` | Enables `--shadow-tls`, `--go`, `--im`, `--fish`, `--neofetch`, `--backports`, `--bbr`, `--byobu`, `--cloud` and `--network-console`. Sets the release to `stable`. |
| `-m`, `--minimal` | Enables `--backports`, `--bbr`, `--cloud` and `--network-console`. Sets the release to `stable`. |
| `--tiny` | Enables `--cloud`, runs `provision`, then runs `tiny --all --yes --skip-reboot`. |
| `--debug` | Keeps the `provision` and `tiny` files and logs in the new system. |
| `-bbr`, `--bbr` | Turns on TCP BBR. |
| `--go`, `--im`, `--fish`, `--neofetch`, `--byobu`, `--socat`, `--docker` | Installs the named tool. |
| `-qa`, `--qemu-guest-agent` | Installs the QEMU guest agent. |
| `-ss`, `--shadowsocks` | Installs Shadowsocks. If Shadowsocks runs on the current host, the script turns this on. |
| `--dss`, `--disable-shadowsocks` | Does not install Shadowsocks. |
| `-ssp`, `--shadowsocks-password`, `-sspt`, `--shadowsocks-port`, `-sspobfs`, `--shadowsocks-obfs-host` | Shadowsocks values. Defaults come from `/etc/shadowsocks/config.json` or `/etc/shadowsocks-libev/config.json`, else random values. |
| `-stls`, `--shadow-tls` | Installs Snell behind Shadow-TLS. |
| `--shadow-tls-port`, `--shadow-tls-password`, `--shadow-tls-obfs-host` | Shadow-TLS values. Defaults come from `/etc/default/shadow-tls`, else random values. |
| `--snell-port`, `--snell-psk`, `--snell-obfs`, `--snell-tfo` | Snell values. Defaults come from `/etc/snell/snell-server.conf`, else random values, `tls` and `true`. |

Random ports are between 10000 and 65535, and the script keeps them different from the SSH port and from each other.

## What it changes

On the current host, the script does these steps:

1. It installs the packages that it needs.
2. It writes the installer kernel and initrd to `/boot/debian-<suite>-<arch>-<timestamp>/`. The initrd contains the preseed file.
3. It copies the GRUB file to `grub.cfg.<timestamp>.bak` next to the original.
4. It replaces `/etc/grub.d/40_custom` with one entry, `Install Debian <suite> <arch>`.
5. It runs `grub-mkconfig` and `grub-reboot` to boot that entry one time.
6. It reboots after 3 seconds.

The installer then does these steps:

1. It erases the disk, or all the disks with `--lvm` or `--jbod`, and partitions them.
2. It installs Debian with `openssh-server`, `build-essential`, `curl`, `wget`, `net-tools`, `git`, `vim`, `tig` and `libpam-systemd`.
3. It creates the user, turns off root login and sets the time zone and NTP server.
4. If you gave a post-install flag, it runs `provision` and writes its log to `/var/log/provision_<timestamp>.log`. Without `--debug`, it deletes the log.
5. It reboots into the new system.

## Notes

- Do not run the script on a host with data that you need. The installer erases the disk with no prompt. With `--lvm` or `--jbod` and no `--disk`, it erases every disk.
- Do not run the script without a plan for console access. If the installer fails, you need the console of your cloud provider to repair the host.
- The script starts at once. It does not ask for confirmation, and it reboots 3 seconds after it finishes.
- `--dry-run` does not reboot and does not update the real GRUB file. It still installs packages, writes to `/boot` and replaces `/etc/grub.d/40_custom`. The next `update-grub` adds the installer entry to the boot menu.
- The script prints the password, the password hash, the generated private key and the proxy passwords to the terminal. Clear the terminal history after the run.
- The script replaces any entries that you had in `/etc/grub.d/40_custom`.
- If the host has 512 MB of RAM or less, the script uses low-memory mode and the cloud kernel.
- `--provision` and `--minimal` set the release to `stable`. Put `--version` after them on the command line to choose another release.
- `-ncp` and `--network-console-password` have no effect. The script always makes a random network console password.
- The random UID has 4 digits and can be lower than 1000. Give `--uid` to choose it.
