# tailscale

A single container that joins your **tailnet** and exposes a **shadowsocks-rust**
server as the external entry point. Point any Shadowsocks client at it and you
transparently reach:

- the container itself,
- every tailnet node (`100.64.0.0/10`),
- any subnet routes the container accepts or advertises.

It follows the same shape as [`blackhole`](../../wego/blackhole): a `run`
host-launcher, a multi-stage `Dockerfile`, a `docker-entrypoint.sh`, and an
externally-supplied secret (here, the tailnet auth key). Shadowsocks is
installed via the repo's own [`ss-rust`](../ss-rust) installer, with the
`obfs-server` plugin for HTTP/TLS obfuscation.

## How it works

```
  SS client ──(shadowsocks + obfs)──▶ ss-server ──▶ container network stack
                                                       │
                                            tailscaled (tun, --accept-routes)
                                                       │
                            tailnet IPs / MagicDNS / advertised subnets
```

`ss-server` dials each target **from inside the container**. Because the
container is a tailnet node, tailnet-destined traffic (100.x addresses and
accepted subnet routes) resolves through `tailscaled` just like any other
route — no per-client tailnet setup required.

Kernel networking mode is used (`/dev/net/tun` + `NET_ADMIN`). If the tun
device is unavailable the entrypoint falls back to userspace networking, in
which case SS → tailnet routing is degraded (a warning is logged).

## Quick start

```bash
# 1. Get a tailnet auth key: https://login.tailscale.com/admin/settings/keys
#    (ephemeral + reusable is convenient for a disposable node)

# 2. First run — build, join the tailnet, expose SS on 8388
./run --authkey tskey-auth-xxxxx --hostname ss-gateway --ss-port 8388

# 3. Read the connection details (auto-generated password is printed here)
docker logs -f tailscale-ss
```

Prefer an env file:

```bash
cp .tailscale.env.example .tailscale.env
$EDITOR .tailscale.env          # set TS_AUTHKEY, SS_* ...
./run --env-file .tailscale.env
```

The tailnet state persists in the `tailscale-ss-state` Docker volume, so after
the first login the auth key is no longer required on restart.

## Options (`./run --help`)

| Flag | Env | Purpose |
|------|-----|---------|
| `--authkey` | `TS_AUTHKEY` | Tailnet auth key (first login only) |
| `--hostname` | `TS_HOSTNAME` | Node name in the tailnet |
| `--routes` | `TS_ROUTES` | Advertise local subnets (subnet router) |
| `--exit-node` | `TS_EXIT_NODE` | Egress through a tailnet exit node |
| `--advertise-exit-node` | `TS_ADVERTISE_EXIT_NODE` | Offer this node as an exit node |
| `--ss-port` | `SS_PORT` | Shadowsocks port (default 8388) |
| `--ss-password` | `SS_PASSWORD` | SS password (auto-generated if blank) |
| `--obfs-host` | `SS_OBFS_HOST` | obfs masquerade host (client-side hint) |
| `--bind` | — | Host bind address for the published port |
| `--host-net` | — | Host networking — SS binds the host's port directly (preserves real client IPs, avoids double-NAT) |
| `--env-file` | — | KEY=VALUE file of the above |
| `--build` | — | Force image rebuild |

Extra tailnet knobs are env-only: `TS_ACCEPT_ROUTES` (default `true`),
`TS_ACCEPT_DNS` (default `false`), `TS_EXTRA_ARGS`, `SS_METHOD`, `SS_MODE`,
`SS_OBFS`. See `.tailscale.env.example`.

## Client configuration

Any Shadowsocks client works. Match what the container logs at startup:

- **server**: the host's public IP
- **server_port**: `SS_PORT`
- **password**: from the logs (or your `SS_PASSWORD`)
- **method**: `chacha20-ietf-poly1305`
- **plugin**: `obfs-local` with `obfs=http;obfs-host=<SS_OBFS_HOST>` (omit if `SS_OBFS=none`)

To reach a tailnet host, use its tailnet IP (or a MagicDNS name if
`TS_ACCEPT_DNS=true`) as the destination — the SS proxy resolves and routes it
inside the container.

## Reaching private LANs

To let SS clients reach a private subnet that lives behind this node, advertise
it and approve the route in the admin console:

```bash
./run --authkey tskey-auth-xxxxx --routes 192.168.1.0/24
```

To reach subnets advertised by *other* tailnet nodes, nothing extra is needed —
`--accept-routes` is on by default.

## Files

| File | Purpose |
|------|---------|
| `run` | Host launcher: builds image, runs the container with tun + published SS port |
| `Dockerfile` | Multi-stage build (ss-rust + tailscale static binaries → Alpine runtime) |
| `docker-entrypoint.sh` | Boots tailscaled, `tailscale up`, then ss-server; supervises both |
| `.tailscale.env.example` | Documented env template |
