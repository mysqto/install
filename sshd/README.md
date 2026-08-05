# sshd

A hardened, single-container **SSH server** you can SSH into on a chosen or
random port. Same shape as [`tailscale`](../tailscale): a `run` host-launcher, a
one-stage `Dockerfile`, a `docker-entrypoint.sh`, and an `install` script wired
into `im`.

- **Key-only login** — passwords fully disabled (`AuthenticationMethods publickey`).
- **Non-root login user** — created on first start (default `dev`).
- **Ban after failed tries** — native OpenSSH `PerSourcePenalties` (≥ 9.8): a
  source that keeps failing is refused for escalating durations. No fail2ban,
  iptables, or `NET_ADMIN` required.
- **Persistent host key** — stored in a volume so the fingerprint is stable
  across recreations.
- **Chosen or random port** — `--port N`, or omit for a Docker-assigned one
  (reported at startup).

## Quick start

```bash
# Fixed port, key from a file
./run --pubkey ~/.ssh/id_ed25519.pub --port 2222

# Random port, keys from GitHub
./run --pubkey-url https://github.com/you.keys

# Inline key, custom user with sudo
./run --key 'ssh-ed25519 AAAA... you@host' --user ops --sudo
```

The startup logs print the published port and the host-key fingerprint:

```bash
docker logs -f sshd-box
```

Then connect:

```bash
ssh -p <port> dev@<host>
```

## Options (`./run --help`)

| Flag | Env | Purpose |
|------|-----|---------|
| `--pubkey <file>` | (mount) | authorized_keys file |
| `--pubkey-url <url>` | `SSH_AUTHORIZED_KEYS_URL` | fetch keys from a URL |
| `--key '<ssh-...>'` | `SSH_AUTHORIZED_KEYS` | inline public key |
| `--user <name>` | `SSH_USER` | login user (default `dev`) |
| `--port <port>` | — | host port (default: random) |
| `--bind <ip>` | — | host bind address (default `0.0.0.0`) |
| `--sudo` | `SSH_SUDO` | passwordless sudo for the user |
| `--build`, `--rebuild` | — | force image rebuild |

Banning / hardening knobs are env-only (see `.sshd.env.example`):
`SSH_MAX_AUTH_TRIES` (3), `SSH_LOGIN_GRACE` (20), `SSH_PENALTY_AUTHFAIL` (20s),
`SSH_PENALTY_MAX` (30m), `SSH_ALLOW_TCP_FORWARDING` (no).

## Via `im`

```bash
im -sshd --pubkey-url https://github.com/you.keys --port 2222
im -sshd --key 'ssh-ed25519 AAAA... you@host' --user ops --sudo
```

`im` installs Docker if missing and runs the container **as the invoking user**
(via the docker group), never as root.

## How the banning works

OpenSSH tracks failures per source address. `PerSourcePenalties authfail:20s
max:30m` adds 20s of penalty per authentication failure, escalating up to 30
minutes; `MaxAuthTries 3` drops a connection after 3 attempts. A brute-forcer is
therefore locked out for growing intervals without any external tooling.

> Note: penalties key on the client's source IP. If Docker's `userland-proxy` is
> enabled (the default on Docker Desktop), published-port traffic is SNAT'd to
> the bridge gateway and all clients look identical — run on Linux with
> `userland-proxy=false` (or host networking) to preserve real client IPs.

## Files

| File | Purpose |
|------|---------|
| `run` | Host launcher: build + `docker run`, publish port 22, report the mapping |
| `Dockerfile` | Alpine + openssh-server, key-only, native penalties |
| `docker-entrypoint.sh` | user + authorized_keys + host keys + sshd_config, runs `sshd -D` |
| `install` | `im`-invoked Docker setup (runs as the invoking user) |
| `.sshd.env.example` | documented env template |
