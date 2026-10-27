# tiny

`tiny` shrinks a fresh Debian install to a small RAM and disk footprint. It applies the eight stages from [TierHive's minimal Debian 13 guide][tiny-ref], which targets about 38 MB of RAM and 275 MB of disk. The script is for Debian 13 on KVM VPS instances. Each stage is idempotent (safe to run twice), and you select the stages that you want.

[tiny-ref]: https://tierhive.com/blog/tierhive-howto/debian-13-minimal-guide-reduce-ram-to-38mb-and-disk-to-275mb

## Requirements

- A Debian system. If `/etc/debian_version` or `apt-get` is missing, the script stops.
- Root. If you are not root, the script stops.
- The `--yes` flag. Without it, the script prints a warning and stops before it changes anything.
- A KVM guest with virtio disk and network. Stage 7 builds the initramfs with `virtio_blk`, `virtio_net` and `ext4` only.

## Usage

Download the script on the Debian host:

```bash
curl -sL debian.lol/tiny -o tiny && chmod +x tiny
```

Run all stages after a fresh install:

```bash
./tiny --all --yes
```

Run only some stages:

```bash
./tiny --grub --strip-packages --tune --yes
```

Run Stage 5 with explicit network values:

```bash
./tiny --ifupdown --interface ens3 --ip 1.2.3.4/24 --gateway 1.2.3.1 --yes
```

To replace OpenSSH with Dropbear, do these steps:

1. Run `./tiny --dropbear --yes`. Dropbear starts on port 22 and OpenSSH stops.
2. Open a new SSH session to the host. This session uses Dropbear.
3. In the new session, run `./tiny --purge-ssh --yes` to remove the OpenSSH packages.

When you give `--tiny` to the `debian` installer, it runs `tiny --all --yes --skip-reboot` after the install. See [DEBIAN-README.md](DEBIAN-README.md).

## Options

If you run `tiny` with no arguments, it prints the help text. The script runs the stages in the order below. The order of the flags on the command line has no effect.

### Stage flags

| Flag | Stage | What it does |
|------|-------|--------------|
| `--all` | 1 to 8 | Enables every stage below except `--purge-ssh`. |
| `--grub` | 1 | Sets `GRUB_TIMEOUT=1`, rewrites `GRUB_CMDLINE_LINUX`, runs `update-grub`, and removes `/boot/grub/locale`. |
| `--dropbear` | 2 | Installs Dropbear, starts it, and stops and disables OpenSSH. It does not remove OpenSSH. |
| `--purge-ssh` | 2b | Purges `openssh-server`, `openssh-sftp-server`, `openssh-client` and `ssh-import-id`. |
| `--strip-cloud` | 3 | Purges cloud-init, unattended-upgrades, netplan, every `python3*` and `libpython3*` package, and disables the apt timers. |
| `--strip-packages` | 4 | Purges vim, man pages, locales, `sudo`, `wget` and other tools. Adds a dpkg filter that skips docs on later installs. |
| `--ifupdown` | 5 | Replaces systemd-networkd and systemd-resolved with ifupdown and a static address. |
| `--strip-services` | 6 | Masks kernel mounts, `systemd-logind` and the `pam_systemd` session. |
| `--initramfs` | 7 | Builds a dependency-only initramfs and writes a module blacklist. |
| `--tune` | 8 | Writes sysctl values, sets block read-ahead to 128 KB, starts busybox `syslogd` and masks journald. |

### Other options

| Flag | Default | What it does |
|------|---------|--------------|
| `--interface IFACE` | Interface of the IPv4 default route | Interface for Stage 5. |
| `--ip CIDR` | Current IPv4 address of the interface | Static address for Stage 5, for example `1.2.3.4/24`. |
| `--gateway IP` | Current IPv4 default gateway | Gateway for Stage 5. |
| `--dns "S1 S2"` | `1.1.1.1 1.0.0.1` | Name servers that Stage 5 writes to `/etc/resolv.conf`. |
| `--block-device DEV` | Parent disk of `/`, then `vda` | Block device name for the read-ahead value in Stage 8. |
| `--keep-mitigations` | Off | Does not add `mitigations=off` to the kernel command line. |
| `--keep-ipv6` | Off | Does not add `ipv6.disable=1` to the kernel command line. |
| `--skip-reboot` | Off | Does not reboot at the end. |
| `-y`, `--yes` | Off | Allows the script to make changes. You must give it. |
| `-h`, `--help` | | Prints the help text. |

The script prints a warning for an unknown flag and continues.

## What it changes

Stage 1 writes this kernel command line to `/etc/default/grub`:

```text
mitigations=off console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0 audit=0 nowatchdog ipv6.disable=1
```

The other stages change these items:

- Stage 2 sets `DROPBEAR_EXTRA_ARGS=""` in `/etc/default/dropbear` and disables `ssh` and `ssh.socket`.
- Stage 3 removes `/var/lib/cloud`.
- Stage 4 writes `/etc/dpkg/dpkg.cfg.d/nodoc`. It deletes `/usr/share/doc` (except copyright files), `/usr/share/man`, `/usr/share/groff`, `/usr/share/info` and `/usr/share/lintian`. It keeps only `en_US` in `/usr/share/locale` and only `Etc/UTC` in `/usr/share/zoneinfo`. It removes `deb-src` from `/etc/apt/sources.list.d/debian.sources`. It installs `procps`.
- Stage 5 rewrites `/etc/resolv.conf`, `/etc/nsswitch.conf` and `/etc/network/interfaces`. It purges `systemd-resolved`, `libnss-resolve` and `dhcpcd-base`. It masks systemd-networkd and deletes `/etc/systemd/network/`.
- Stage 6 disables `systemd-timesyncd`, `fstrim.timer` and the `e2scrub` units. It installs `reboot` and `poweroff` wrappers in `/usr/local/sbin`.
- Stage 7 writes `/etc/initramfs-tools/modules`, sets `MODULES=dep`, writes `/etc/modprobe.d/blacklist-vps.conf` and runs `update-initramfs -u -k all`.
- Stage 8 writes `/etc/sysctl.d/90-minvps.conf` and adds the `readahead.service` and `syslogd.service` units.

After the stages, the script deletes the apt lists and caches. Then it waits 5 seconds and reboots, unless you give `--skip-reboot`. Press Ctrl-C during the 5 seconds to cancel the reboot. The kernel command line, the initramfs and the module blacklist take effect after the reboot.

## Notes

- Do not run `--purge-ssh` from an OpenSSH session before you connect through Dropbear. If Dropbear does not start, you lose SSH access to the host.
- Do not run Stage 5 on a host that needs DHCP to keep its address. Stage 5 writes the current address as a static address and removes `dhcpcd-base`. If the address changes later, the host loses its network.
- If Stage 5 cannot find the interface, the address or the gateway, it skips itself. Give `--interface`, `--ip` and `--gateway` to run it in that case.
- Stage 5 does not restart the network. The new network configuration takes effect after the reboot.
- Stage 4 removes `sudo`. If your user needs `sudo`, install it again after the run.
- Stage 8 masks journald. `journalctl` has no logs after the reboot. Busybox `syslogd` keeps the log in a 64 KB ring buffer that you read with `logread`.
- Stage 1 adds `mitigations=off`, which turns off the kernel protections against CPU side-channel attacks. Give `--keep-mitigations` to keep them.
- Stage 3 removes all Python 3 packages. Tools that need Python stop working.
- The script has no undo step. Take a snapshot of the VPS before you run it.
