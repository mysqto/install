# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this directory.

## Project Overview

A hardened single-container SSH server. Key-only login (passwords disabled), a
non-root login user, and native OpenSSH brute-force banning
(`PerSourcePenalties`, ≥ 9.8 — no fail2ban/iptables/NET_ADMIN). The container's
port 22 is published on a chosen or random host port. Public keys and the login
user are supplied at runtime; host keys persist in a volume. Follows the same
conventions as `../tailscale`.

## Architecture

### Dockerfile (single stage, Alpine)
`openssh-server` + `openssh-keygen`, `bash`, `sudo`, `tini`, `curl`. Host keys
volume at `/etc/ssh/keys`. No special capabilities needed.

### Entry point (`docker-entrypoint.sh`)
1. Create the non-root `SSH_USER` (rejects `root`); optional passwordless sudo.
2. Assemble `authorized_keys` from `SSH_AUTHORIZED_KEYS` (inline, `\n`-separated),
   a mounted `/config/authorized_keys`, and/or `SSH_AUTHORIZED_KEYS_URL`. Errors
   if no valid key is found.
3. Generate/persist ed25519 + rsa host keys under `/etc/ssh/keys`.
4. Render `/etc/ssh/sshd_config` (key-only + penalties), validate with `sshd -t`.
5. `exec sshd -D -e` (foreground, logs to docker).

### Host launcher (`run`) / installer (`install`)
`run` builds + `docker run`s locally; `install` is the `im`-invoked path that
fetches the build context from base_url and runs as the invoking user
(`SUDO_USER` via the docker group). Port publishing: `-p bind:PORT:22` when
`--port` is given, else `-p bind::22` (random) discovered via `docker port`.

## Key environment variables

| Var | Default | Purpose |
|-----|---------|---------|
| `SSH_USER` | `dev` | non-root login user |
| `SSH_SUDO` | `false` | passwordless sudo for the user |
| `SSH_AUTHORIZED_KEYS` | — | inline pubkey(s), `\n`-separated |
| `SSH_AUTHORIZED_KEYS_URL` | — | fetch authorized_keys from a URL |
| `SSH_MAX_AUTH_TRIES` | `3` | attempts per connection |
| `SSH_LOGIN_GRACE` | `20` | seconds to authenticate |
| `SSH_PENALTY_AUTHFAIL` | `20s` | penalty added per auth failure |
| `SSH_PENALTY_MAX` | `30m` | penalty ceiling |
| `SSH_ALLOW_TCP_FORWARDING` | `no` | allow forwarding/tunneling |

## Common Commands

```bash
./run --pubkey ~/.ssh/id_ed25519.pub --port 2222
./run --pubkey-url https://github.com/you.keys        # random port
im  -sshd --pubkey-url https://github.com/you.keys --port 2222

docker logs -f sshd-box                                # port + host-key fingerprint
docker exec sshd-box sshd -T | grep -Ei 'password|persource|maxauth'   # verify hardening
```

## Gotchas
- `PerSourcePenalties` keys on the client source IP. Docker `userland-proxy=true`
  (default on Docker Desktop) SNATs published-port traffic to the bridge gateway,
  collapsing all clients to one IP — use `--host-net` (host networking; sshd binds
  `SSH_PORT` directly, must not be 22, and `--hostname` is dropped since it
  conflicts with host networking) or run on Linux with `userland-proxy=false`.
- `docker --env-file` does not strip inline `#` comments; keep the env file's
  comments on their own lines.
- Login is key-only by construction (`AuthenticationMethods publickey`,
  `PasswordAuthentication no`); there is no password fallback — a valid pubkey
  source is mandatory or the container exits.
