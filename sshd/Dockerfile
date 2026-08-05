# Hardened SSH server container.
#
# Key-only login (no passwords), native brute-force banning via OpenSSH's
# PerSourcePenalties (>= 9.8 — no fail2ban / iptables / NET_ADMIN needed), and
# a persistent host key. Publish the container's port 22 on a chosen or random
# host port.

ARG ALPINE_VERSION=3.21
FROM alpine:${ALPINE_VERSION} AS application

RUN apk add --no-cache \
    openssh-server openssh-keygen \
    bash sudo ca-certificates tzdata tini curl

# Host keys live in a volume so the fingerprint is stable across recreations.
RUN mkdir -p /etc/ssh/keys /config
VOLUME /etc/ssh/keys

# Runtime configuration (SSH_USER, SSH_AUTHORIZED_KEYS[_URL], SSH_SUDO,
# SSH_MAX_AUTH_TRIES, SSH_PENALTY_*, ...) is supplied with -e; the entrypoint
# provides sane defaults. Not declared as ENV here — the AUTH/KEY substrings
# trip buildkit's SecretsUsedInArgOrEnv heuristic. See .sshd.env.example.

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Internal listen port is always 22; the host maps a chosen/random port to it.
EXPOSE 22

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/docker-entrypoint.sh"]
