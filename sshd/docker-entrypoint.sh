#!/bin/bash
# Hardened SSH server entry point.
#
# - key-only login (no passwords)
# - a single non-root login user
# - native brute-force banning (OpenSSH PerSourcePenalties + MaxAuthTries)
# - persistent host keys under /etc/ssh/keys
set -uo pipefail

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
info()  { echo -e "\033[32m[$(timestamp)] INFO: $*\033[0m"; }
warn()  { echo -e "\033[33m[$(timestamp)] WARN: $*\033[0m" >&2; }
error() { echo -e "\033[31m[$(timestamp)] ERROR: $*\033[0m" >&2; exit 1; }

SSH_USER="${SSH_USER:-dev}"
KEYS_DIR=/etc/ssh/keys

# ---------------------------------------------------------------------------
# Login user
# ---------------------------------------------------------------------------
case "$SSH_USER" in
    root|"" ) error "SSH_USER must be a non-root name (got '${SSH_USER}')" ;;
    *[!a-z0-9_-]* ) error "SSH_USER '${SSH_USER}' has invalid characters" ;;
esac

if ! id "$SSH_USER" >/dev/null 2>&1; then
    info "creating user '$SSH_USER'"
    adduser -D -s /bin/bash "$SSH_USER" || error "failed to create user $SSH_USER"
    passwd -u "$SSH_USER" >/dev/null 2>&1 || true   # unlock (login is key-only anyway)
fi

if [ "${SSH_SUDO:-false}" = "true" ]; then
    info "granting passwordless sudo to '$SSH_USER'"
    echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$SSH_USER"
    chmod 440 /etc/sudoers.d/"$SSH_USER"
fi

# ---------------------------------------------------------------------------
# authorized_keys — from env, mounted file, and/or URL (all that are present)
# ---------------------------------------------------------------------------
home_dir="$(getent passwd "$SSH_USER" | cut -d: -f6)"
ssh_dir="${home_dir}/.ssh"
auth_file="${ssh_dir}/authorized_keys"
mkdir -p "$ssh_dir"
: > "$auth_file"

if [ -n "${SSH_AUTHORIZED_KEYS:-}" ]; then
    # allow literal "\n" separators as well as real newlines
    printf '%b\n' "$SSH_AUTHORIZED_KEYS" >> "$auth_file"
    info "loaded keys from SSH_AUTHORIZED_KEYS"
fi
if [ -f /config/authorized_keys ]; then
    cat /config/authorized_keys >> "$auth_file"
    info "loaded keys from /config/authorized_keys"
fi
if [ -n "${SSH_AUTHORIZED_KEYS_URL:-}" ]; then
    if curl -fsSL "$SSH_AUTHORIZED_KEYS_URL" >> "$auth_file"; then
        info "loaded keys from SSH_AUTHORIZED_KEYS_URL"
    else
        warn "failed to fetch SSH_AUTHORIZED_KEYS_URL"
    fi
fi

# strip blank lines / comments-only; require at least one real key
sed -i '/^[[:space:]]*$/d' "$auth_file"
if ! grep -qE '^(ssh-|ecdsa-|sk-)' "$auth_file"; then
    error "no valid public keys provided — set SSH_AUTHORIZED_KEYS, mount /config/authorized_keys, or set SSH_AUTHORIZED_KEYS_URL"
fi

chmod 700 "$ssh_dir"; chmod 600 "$auth_file"
chown -R "$SSH_USER":"$SSH_USER" "$ssh_dir"
info "$(grep -cE '^(ssh-|ecdsa-|sk-)' "$auth_file") authorized key(s) installed for $SSH_USER"

# ---------------------------------------------------------------------------
# Persistent host keys
# ---------------------------------------------------------------------------
mkdir -p "$KEYS_DIR"
if ! ls "$KEYS_DIR"/ssh_host_*_key >/dev/null 2>&1; then
    info "generating host keys in $KEYS_DIR"
    ssh-keygen -t ed25519 -f "$KEYS_DIR/ssh_host_ed25519_key" -N '' -q
    ssh-keygen -t rsa -b 4096 -f "$KEYS_DIR/ssh_host_rsa_key" -N '' -q
fi
chmod 600 "$KEYS_DIR"/ssh_host_*_key
chmod 644 "$KEYS_DIR"/ssh_host_*_key.pub 2>/dev/null || true

# ---------------------------------------------------------------------------
# sshd_config
# ---------------------------------------------------------------------------
config=/etc/ssh/sshd_config
cat > "$config" <<EOF
Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

HostKey ${KEYS_DIR}/ssh_host_ed25519_key
HostKey ${KEYS_DIR}/ssh_host_rsa_key

# --- Key-only authentication ---
PubkeyAuthentication yes
AuthenticationMethods publickey
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
AllowUsers ${SSH_USER}
AuthorizedKeysFile .ssh/authorized_keys

# --- Brute-force banning (native, OpenSSH >= 9.8) ---
MaxAuthTries ${SSH_MAX_AUTH_TRIES:-3}
LoginGraceTime ${SSH_LOGIN_GRACE:-20}
PerSourcePenalties authfail:${SSH_PENALTY_AUTHFAIL:-20s} max:${SSH_PENALTY_MAX:-30m}
MaxStartups 10:30:60

# --- Hygiene ---
X11Forwarding no
AllowTcpForwarding ${SSH_ALLOW_TCP_FORWARDING:-no}
AllowAgentForwarding no
PermitTunnel no
PrintMotd no
ClientAliveInterval 120
ClientAliveCountMax 2
LogLevel VERBOSE
Subsystem sftp internal-sftp
EOF

# Validate the config before launching.
/usr/sbin/sshd -t -f "$config" || error "sshd config validation failed"

info "SSH server ready:"
info "  user            : $SSH_USER"
info "  auth            : publickey only (passwords disabled)"
info "  max auth tries  : ${SSH_MAX_AUTH_TRIES:-3}"
info "  penalties       : authfail=${SSH_PENALTY_AUTHFAIL:-20s} max=${SSH_PENALTY_MAX:-30m}"
info "  host key (ed25519 fingerprint):"
ssh-keygen -lf "$KEYS_DIR/ssh_host_ed25519_key.pub" 2>/dev/null | sed 's/^/    /'

# -D: foreground, -e: log to stderr (docker logs)
exec /usr/sbin/sshd -D -e -f "$config"
