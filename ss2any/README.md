# ss2any

A tiny docker container that exposes a **Shadowsocks** endpoint and forwards
all traffic through an **arbitrary upstream proxy** described by a single
URL (`vless://`, `trojan://`, `vmess://`, `ss://`, `hysteria2://`, `tuic://`).

Built on a single static binary — [sing-box](https://sing-box.sagernet.org/) —
plus a small Python script that converts the proxy URL into a sing-box JSON
config at startup.

```
[ SS client ] --SS--> [ ss2any container ] --VLESS / Trojan / VMess / ... --> [ upstream proxy ]
```

## Why not ss-rust?

`shadowsocks-rust` has no built-in VLESS/Trojan/VMess outbound, so chaining
would need two processes (`ss-server` + `vless-client`) glued together by a
local SOCKS5 bridge. `sing-box` natively supports SS inbound + N outbound
protocols in one process and ~20 MB.

## Quick start

### Single upstream (one SS port, one upstream)

```bash
cp .ss2any.env.example .ss2any.env
$EDITOR .ss2any.env          # set PROXY_LINK=...
./run --env-file .ss2any.env --port 8388
# or:  ./run --link 'vless://...' --port 8388
docker logs -f ss2any         # generated password is logged once
```

### Multiple upstreams / proxy chains (one container, N SS ports)

```bash
cp ss2any.yaml.example ss2any.yaml
$EDITOR ss2any.yaml          # define inbounds, upstreams, chains
./run --config ss2any.yaml
```

The host launcher asks the parser which ports the YAML declares
(`generate-config.py plan-ports`) and publishes only those — no port range
guessing, no host networking, `docker ps` shows exactly what's open.

Each inbound routes to either an upstream (1-hop) or a chain. Chains use
sing-box's `detour` field, so a chain `[A, B, C]` dials
client → A → B → C → internet.

## Environment variables (single-link mode only)

| Variable          | Default                       | Notes                                       |
|-------------------|-------------------------------|---------------------------------------------|
| `PROXY_LINK`      | *(required)*                  | Upstream proxy URL                          |
| `PROXY_LINK_FILE` | *(unset)*                     | Alternative to `PROXY_LINK` env             |
| `SS_PORT`         | `8388`                        | SS listen port                              |
| `SS_METHOD`       | `chacha20-ietf-poly1305`      | SS cipher                                   |
| `SS_PASSWORD`     | *(generated)*                 | Auto-generated and logged if blank          |
| `SS_NETWORK`      | `tcp`                         | `tcp` / `udp` / `tcp_and_udp`               |
| `LOG_LEVEL`       | `info`                        | sing-box log level                          |
| `SS2ANY_CONFIG`   | `/config/ss2any.yaml`         | Path inside container; ignored if absent    |

In multi-inbound (YAML) mode, `SS_*` env vars are ignored — each inbound's
port/password/method/network comes from the YAML.

## Files

| File                    | Purpose                                                                |
|-------------------------|------------------------------------------------------------------------|
| `Dockerfile`            | Alpine + sing-box binary + python3 + py3-yaml                          |
| `docker-entrypoint.sh`  | Runs `generate-config.py generate`, validates, execs `sing-box run`    |
| `generate-config.py`    | URL → sing-box JSON parser. Subcommands: `plan-ports`, `generate`      |
| `run`                   | Host-side launcher. Calls `plan-ports` to build docker `-p` flags      |
| `.ss2any.env.example`   | Template env file (single-link mode)                                   |
| `ss2any.yaml.example`   | Template config (multi-inbound + chains)                               |

## Extending to more inbound/outbound protocols

- **Outbound**: already covers vless/trojan/vmess/ss/hysteria2/tuic.
  Add a new `parse_<scheme>(url)` in `generate-config.py` and register it
  in `PARSERS`.
- **Inbound** (e.g. expose SOCKS5/HTTP/Trojan instead of SS): edit
  `build_config()` in `generate-config.py` — the route already final-hops
  everything through `proxy-out`.
