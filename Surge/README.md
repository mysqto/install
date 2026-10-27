# Surge

This directory holds tools for [Surge](https://nssurge.com) clients. `gc` and `bgc` connect to proxy servers over SSH and print Surge proxy lines for them. `Rules/Oracle.list` is a Surge rule list. The server installer for Snell is in [Snell](Snell/README.md).

## Requirements

- On the local machine: `bash`, `ssh`, `curl`, and `python3`. `python3` makes the flag emoji in proxy names and converts latency values.
- For `gc -P`: `sshpass`.
- On each server: `curl`, and an SSH user that can read the proxy configuration files. See [What gc reads](#what-gc-reads).
- For `bgc` without `-s`: the `im` command on the `PATH` of the SSH user on each server.

## gc

`gc` connects to one server, or to all hosts in `~/.ssh/config`, and prints one Surge proxy line for each proxy that it finds.

### Usage

Download the script:

```bash
curl -sL debian.lol/Surge/gc -o gc && chmod +x gc
```

Generate lines for one host:

```bash
./gc my-server
./gc -u root -p 22 203.0.113.10
./gc -i ~/.ssh/id_ed25519 user@host
```

Generate lines for all hosts in `~/.ssh/config`:

```bash
./gc
```

In the all-hosts mode, `gc` reads `~/.ssh/config` and the files that its `Include` lines name. It skips includes with `orbstack`, `multipass`, or `lima` in the path. It also skips these hosts:

- Wildcard patterns.
- `localhost`, loopback, private, and link-local addresses.
- `orb`, `github`, `gitlab`, and `bitbucket`, with or without `.com` or `.org`.
- Names that contain `iMac` or `MacBook`, and names that end in `.local`.

### Options

| Flag | Default | What it does |
|------|---------|--------------|
| `-u`, `--user` | from `~/.ssh/config` | SSH user. Single-host mode only |
| `-p`, `--port` | from `~/.ssh/config` | SSH port. Single-host mode only |
| `-i`, `--identity` | from `~/.ssh/config` | SSH private key. Single-host mode only |
| `-P`, `--password` | | SSH password, through `sshpass` |
| `-o`, `--output` | | Also writes the lines to this file |
| `-a`, `--all` | | Processes all hosts. With no host, `gc` does this by default |
| `-h`, `--help` | | Shows the help text |

### What gc reads

On each server, `gc` reads these files with `cat` over SSH:

- `/etc/shadowsocks/config.json`. If that file is empty or missing, `gc` reads `/etc/shadowsocks-libev/config.json`.
- `/etc/snell/snell-server.conf`.
- `/etc/default/shadow-tls`.

It gets the public IP address of the server from `ifconfig.me`, `icanhazip.com`, or `ipinfo.io/ip`. Then it reads the country and the organization from `ipinfo.io`. It names each proxy `<flag><organization>-<type>`, for example `-Snell`, `-Snell+ShadowTLS`, or `-SS`.

To pick a `test-url`, `gc` runs `curl` on the server against a list of connectivity check URLs and keeps the fastest. For a server in China, it uses a list of Chinese URLs.

### Output

`gc` prints lines like these:

```text
<name> = snell, <host>, <port>, psk=<psk>, version=<n>, reuse=true, tfo=true, test-url=<url>
<name> = ss, <host>, <port>, encrypt-method=<method>, password=<password>, tfo=true, test-url=<url>, block-quic=off, udp-relay=true
```

If shadow-tls is configured, the Snell line uses the shadow-tls port and adds `shadow-tls-password`, `shadow-tls-sni`, and `shadow-tls-version=3`. If the Shadowsocks configuration has `obfs` plugin options, the `ss` line adds `obfs` and `obfs-host`.

Copy the lines into the `[Proxy]` section of your Surge profile.

## bgc

`bgc` runs `gc` for a list of hosts. Before it runs `gc` for a host, it connects over SSH and runs `im -stls`. That command installs or updates Snell with shadow-tls on the server through [Snell/install](Snell/README.md).

### Usage

`bgc` runs `gc` from its own directory. Download both scripts into the same directory:

```bash
curl -sL debian.lol/Surge/gc -o gc && chmod +x gc
curl -sL debian.lol/Surge/bgc -o bgc && chmod +x bgc
```

Set up the servers and generate lines:

```bash
./bgc server1 server2 server3
./bgc -u root 203.0.113.10 203.0.113.11
```

Generate lines only, with no setup:

```bash
./bgc -s server1 server2
./bgc -o proxies.conf server1 server2
```

### Options

| Flag | Default | What it does |
|------|---------|--------------|
| `-u`, `--user` | `poiuy` | SSH user |
| `-p`, `--port` | `22` | SSH port |
| `-s`, `--skip-setup` | off | Does not run `im -stls` |
| `-o`, `--output` | | Also writes the lines to this file |
| `-h`, `--help` | | Shows the help text |

If `im -stls` fails on a host, `bgc` shows a warning and continues with `gc`. At the end, it prints the number of hosts that succeeded and failed, then all proxy lines.

## Rules/Oracle.list

`Rules/Oracle.list` is a Surge rule list for Oracle and Oracle Cloud domains. It is at `https://debian.lol/Surge/Rules/Oracle.list`. It has these rules:

- `DOMAIN-SUFFIX` for `oracle.com`, `oraclecloud.com`, and `oracleinfinity.io`.
- `DOMAIN-KEYWORD` for `oracle`, `oci`, and `oraclecloud`.

## Notes

- Keep the output private. The proxy lines hold the Snell PSK, the shadow-tls password, and the Shadowsocks password. `-o` writes them to a file with your default file permissions.
- `gc` and `bgc` connect with `StrictHostKeyChecking=no`. They accept any host key without a check.
- `gc -P` does not work at this time. `gc` always adds `BatchMode=yes`, and that option turns off password login.
- The `DOMAIN-KEYWORD,oci` rule matches all domains that contain `oci`, for example domains with `social` or `associated` in the name.
- If the SSH user cannot read the files in [What gc reads](#what-gc-reads), `gc` finds no proxy and skips the host.
