# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this directory.

## Project Overview

A single-container WireGuard **client peer** that doubles as a Shadowsocks entry
point. `wg-quick` brings up `wg0` (kernel WireGuard, `wireguard-go` fallback
over `/dev/net/tun`); a `shadowsocks-rust` server (`obfs-server` plugin) is the
externally-reachable front door. Because `ss-server` dials targets from inside
the container, whatever the tunnel routes is what external SS clients reach —
everything for the default full tunnel, or a specific LAN when `AllowedIPs` is
narrowed.

The client private key is supplied externally (never baked into the image) — via
`--conf`, `--private-key`, `--env-file`, or `WG_CONFIG`. Client-peer only: for a
WireGuard **server** use `../wireguard` (systemd, host-level). Follows the same
conventions as `../tailscale`.

## Architecture

### Multi-Stage Dockerfile
- **Builder** (Alpine): installs shadowsocks-rust + simple-obfs via the repo's
  own `https://debian.lol/ss-rust` installer, and compiles `wireguard-go` from
  `golang.zx2c4.com/wireguard`. The upstream main package sits at the module
  root, so `go install` produces a binary called `wireguard` — it is installed
  as `wireguard-go`, the name `wg-quick` looks for. Alpine does not package it,
  and upstream's `0.0.x` git tags are absent from the Go module proxy, so
  `WIREGUARD_GO_VERSION` defaults to `latest`.
- **Application** (Alpine): runtime with `tini`, `libev`, `wireguard-tools`
  (+`-wg-quick`), `openresolv`, `iptables`, `iproute2`, `jq`, `pwgen`, the three
  copied binaries, and a `sysctl` shim.

### The `sysctl` shim
`/proc/sys` is read-only in an unprivileged container, so `wg-quick`'s
`sysctl -q net.ipv4.conf.all.src_valid_mark=1` (only reached for a default-route
`AllowedIPs`) fails and, because `wg-quick` runs under `set -e`, aborts the whole
bring-up. `/usr/local/bin/sysctl` sits ahead of `/sbin` in `PATH` and exits 0
when the requested value is already in effect — which is what `run`'s
`--sysctl net.ipv4.conf.all.src_valid_mark=1` arranges — and fails loudly with
the fix otherwise.

### Entry point (`docker-entrypoint.sh`)
1. `render_wg_config` — `/config/wg0.conf` > `WG_CONFIG` (base64 or raw) >
   discrete `WG_*` vars > the config persisted in the `/etc/wireguard` volume.
2. `prepare_conf` — strip `DNS=` (see below), apply `WG_TABLE`, detect whether
   `AllowedIPs` is a default route.
3. `probe_wg_mode` — try `ip link add type wireguard` to learn (and log) whether
   the run will be kernel or userspace, and pre-check `/dev/net/tun` +
   `wireguard-go` so `wg-quick`'s own fallback can succeed. `wg-quick` decides
   the mode itself; `WG_QUICK_USERSPACE_IMPLEMENTATION` only names the fallback
   binary and cannot force userspace.
4. `start_wireguard` — `wg-quick up`, then `fix_return_routing`.
5. `apply_dns` — write `/etc/resolv.conf` from the tunnel DNS. Runs *after* the
   tunnel is up so a hostname `Endpoint` resolves with docker's DNS first.
6. `resolve_probe_target` + `validate_probe_target` — pick a ping target and
   prove it answers once, or disable probing.
7. `start_shadowsocks` — render `/etc/shadowsocks/config.json` with `jq` (obfs
   plugin optional), launch `ss-server`.
8. Supervise loop — probe the tunnel and repair it in place; if `ss-server` dies
   or the tunnel never recovers, exit so docker's restart policy restarts the
   container.

### `fix_return_routing` — the load-bearing bit
With a default-route `AllowedIPs`, `wg-quick` installs `ip rule` pref 32764/32765
(`suppress_prefixlength 0` + table 51820) so everything goes into the tunnel.
Replies to **inbound** SS connections then leave via `wg0` with the wrong source
address and every session hangs after the TCP handshake. The fix is
`ip rule add from <local-non-wg-addr> lookup main pref 90`. Locally *originated*
connections are unaffected: their source is not chosen until after the route
lookup, so they still take the tunnel.

Note that `suppress_prefixlength 0` only hides *default* routes, so clients on a
directly-connected subnet keep working without the rule — a test using an
on-subnet SS client cannot detect the bug. The real case is an external client
DNAT'd in by docker, which keeps its own (off-subnet) source address. Verify
with `ip route get 8.8.8.8 from <container-ip>`: `dev eth0` with the rule,
`dev wg0 table 51820` without it.

### Host launcher (`run`) / installer (`install`)
`run` builds the image if missing, then `docker run -d` with
`--cap-add NET_ADMIN`, `--device /dev/net/tun`,
`--sysctl net.ipv4.conf.all.src_valid_mark=1`, a named state volume
(`wg-ss-state` at `/etc/wireguard`), and the SS port published TCP+UDP.
Explicit CLI flags override values from `--env-file`. `install` is the
`curl`-pipeable variant used by `im -wgss`: it resolves `base_url`, installs
docker as root only if missing, and builds/runs as the invoking user.

There is deliberately **no `--host-net`**: a full-tunnel `AllowedIPs` in the
host's network namespace would reroute the entire host.

## Key environment variables

| Var | Default | Purpose |
|-----|---------|---------|
| `WG_PRIVATE_KEY` | — | Client private key (secret; runtime only) |
| `WG_ADDRESS` | — | This peer's tunnel address, e.g. `10.0.0.2/32` |
| `WG_PEER_PUBLIC_KEY` | — | Server public key |
| `WG_ENDPOINT` | — | Server `host:port` |
| `WG_PRESHARED_KEY` | — | Optional PSK (secret; runtime only) |
| `WG_CONFIG` | — | Whole config, base64 or raw with `\n` (secret) |
| `WG_ALLOWED_IPS` | `0.0.0.0/0,::/0` | What routes into the tunnel |
| `WG_MTU` | `1420` | Tunnel MTU |
| `WG_KEEPALIVE` | `25` | `PersistentKeepalive` |
| `WG_TABLE` | — | wg-quick table, or `off` |
| `WG_DNS` | — | Override the resolver used in the container |
| `WG_USE_DNS` | `true` | Adopt tunnel DNS at all |
| `WG_PROBE` | `true` | Enable the liveness probe |
| `WG_PROBE_TARGET` | tunnel gw | Ping target through the tunnel (else network+1 of `WG_ADDRESS`, else `1.1.1.1` for a full tunnel, else first `AllowedIPs` host) |
| `WG_PROBE_INTERVAL` | `30` | Seconds between probes |
| `WG_PROBE_FAILURES` | `3` | Misses before bouncing `wg0` |
| `WG_MAX_RESTARTS` | `5` | Bounces before exiting the container |
| `WG_HANDSHAKE_TIMEOUT` | `180` | Stale-handshake age when no probe target |
| `SS_PORT` | `8388` | Shadowsocks port |
| `SS_PASSWORD` | auto | SS password (generated + logged if blank) |
| `SS_METHOD` | `chacha20-ietf-poly1305` | AEAD cipher |
| `SS_MODE` | `tcp_and_udp` | `tcp_only` / `udp_only` / `tcp_and_udp` |
| `SS_OBFS` | `http` | `http` / `tls` / `none` |
| `SS_OBFS_HOST` | — | Client-side masquerade host (logged only) |

## Common Commands

```bash
# First run from a provider / wg-client config
./run --conf ~/wg0.conf --ss-port 8388

# Discrete values, split tunnel
./run --private-key "$(cat client.key)" --address 10.0.0.2/32 \
      --peer-key SERVER_PUBKEY --endpoint vpn.example.com:51820 \
      --allowed-ips 10.0.0.0/24

# From env file / force rebuild / pin wireguard-go
./run --env-file .wg-ss.env
./run --build ...
docker build --build-arg WIREGUARD_GO_VERSION=v0.0.0-20260522210424-ecfc5a8d5446 -t wg-ss .

# End-to-end test (real wg server + a target only reachable via the tunnel)
./test-docker.sh --recovery

# Logs (SS password prints here) / tunnel status
docker logs -f wg-ss
docker exec wg-ss wg show
docker exec wg-ss ip rule list
```

## Gotchas
- Requires `/dev/net/tun` + `NET_ADMIN`. Unlike `../tailscale` there is no
  userspace-networking degraded mode: without a tun device the entrypoint fails
  fast, because `wg-quick` has nothing to fall back to.
- The default `AllowedIPs` includes `::/0`; `wg-quick` adds IPv6 routes and rules
  for it, which succeeds in a container with no global IPv6 address.
- A `DNS=` line may carry search domains as well as addresses — only addresses
  are copied into `/etc/resolv.conf`.
- `/etc/resolv.conf` is a docker bind mount: truncate it in place (`>`), never
  replace it (`sed -i` fails with EBUSY).
- Alpine's `alpine:3.21` busybox has no `httpd` applet, which matters when
  building throwaway test targets.
- `docker --env-file` does NOT strip inline `#` comments — the entrypoint
  `_clean()`s the constrained fields, but `.wg-ss.env` must keep comments on
  their own lines.
