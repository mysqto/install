# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this directory.

## Project Overview

A single-container Tailscale node that doubles as a Shadowsocks entry point.
`tailscaled` joins the tailnet (kernel mode over `/dev/net/tun`); a
`shadowsocks-rust` server (`obfs-server` plugin) is the externally-reachable
front door. Because `ss-server` dials targets from inside the container and the
node runs with `--accept-routes`, external SS clients transparently reach the
container, tailnet IPs (`100.64.0.0/10`), and advertised subnet routes.

The tailnet auth key is supplied externally (never baked into the image) — via
`--authkey`, `--env-file`, or `TS_AUTHKEY`. Follows the same conventions as
`../../wego/blackhole`.

## Architecture

### Multi-Stage Dockerfile
- **Builder** (Alpine): installs shadowsocks-rust + simple-obfs via the repo's
  own `https://debian.lol/ss-rust` installer, and fetches the static
  `tailscale`/`tailscaled` binaries from `pkgs.tailscale.com` (version resolved
  from the stable JSON feed unless `TAILSCALE_VERSION` is pinned).
- **Application** (Alpine): runtime with `tini`, `libev`, `iptables`,
  `iproute2`, `jq`, `pwgen`, and the four copied binaries.

### Entry point (`docker-entrypoint.sh`)
1. `ensure_tun` — use `/dev/net/tun`, create it, or fall back to
   `userspace-networking`.
2. `start_tailscaled` — launch daemon, wait for its local API socket.
3. `tailscale_up` — `tailscale up` with `--accept-routes` / auth key / optional
   subnet-route / exit-node flags; enables `ip_forward` when routing for others.
4. `start_shadowsocks` — render `/etc/shadowsocks/config.json` with `jq`
   (obfs plugin optional), launch `ss-server`.
5. Supervise loop — if either child dies, tear down so Docker's restart policy
   restarts the container.

### Host launcher (`run`)
Builds the image if missing, then `docker run -d` with `--cap-add NET_ADMIN`,
`--device /dev/net/tun`, a named state volume (`tailscale-ss-state`), and the SS
port published TCP+UDP. Explicit CLI flags override values from `--env-file`.

## Key environment variables

| Var | Default | Purpose |
|-----|---------|---------|
| `TS_AUTHKEY` | — | Tailnet auth key (first login only; state persists after) |
| `TS_HOSTNAME` | container id | Node name |
| `TS_ACCEPT_ROUTES` | `true` | Install subnet routes from other nodes |
| `TS_ACCEPT_DNS` | `false` | Let tailscaled manage `/etc/resolv.conf` |
| `TS_ROUTES` | — | Advertise local subnets (enables ip_forward) |
| `TS_ADVERTISE_EXIT_NODE` | `false` | Offer node as exit node |
| `TS_EXIT_NODE` | — | Egress through another exit node |
| `TS_EXTRA_ARGS` | — | Appended verbatim to `tailscale up` |
| `SS_PORT` | `8388` | Shadowsocks port |
| `SS_PASSWORD` | auto | SS password (generated + logged if blank) |
| `SS_METHOD` | `chacha20-ietf-poly1305` | AEAD cipher |
| `SS_MODE` | `tcp_and_udp` | `tcp` / `udp` / `tcp_and_udp` |
| `SS_OBFS` | `http` | `http` / `tls` / `none` |
| `SS_OBFS_HOST` | — | Client-side masquerade host (logged only) |

## Common Commands

```bash
# First run
./run --authkey tskey-auth-xxxxx --hostname ss-gateway --ss-port 8388

# From env file
./run --env-file .tailscale.env

# Subnet router for a private LAN
./run --authkey tskey-auth-xxxxx --routes 192.168.1.0/24

# Force rebuild / pin tailscale version
./run --build ...
docker build --build-arg TAILSCALE_VERSION=1.80.0 -t tailscale-ss .

# Logs (SS password prints here) / status
docker logs -f tailscale-ss
docker exec tailscale-ss tailscale --socket=/var/run/tailscale/tailscaled.sock status
```

## Gotchas
- Requires `/dev/net/tun` + `NET_ADMIN` for kernel-mode routing; without them SS
  → tailnet routing is degraded (userspace fallback, warned in logs).
- simple-obfs's *server* has no `obfs-host` flag — `SS_OBFS_HOST` is a client
  setting; the entrypoint only logs it.
- Auth key is only needed for the first login; the `tailscale-ss-state` volume
  persists the node identity afterwards.
