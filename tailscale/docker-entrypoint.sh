#!/bin/bash
# Tailscale node + Shadowsocks entry point.
#
# Boots tailscaled (kernel mode over /dev/net/tun, userspace fallback), joins
# the tailnet, then runs a shadowsocks-rust server that external clients use to
# reach the container / tailnet / advertised subnets.
set -uo pipefail

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
info()  { echo -e "\033[32m[$(timestamp)] INFO: $*\033[0m"; }
warn()  { echo -e "\033[33m[$(timestamp)] WARN: $*\033[0m" >&2; }
error() { echo -e "\033[31m[$(timestamp)] ERROR: $*\033[0m" >&2; exit 1; }

TS_STATE_DIR="${TS_STATE_DIR:-/var/lib/tailscale}"
TS_STATE_FILE="${TS_STATE_DIR}/tailscaled.state"
TS_SOCKET="${TS_SOCKET:-/var/run/tailscale/tailscaled.sock}"
TS_TUN="${TS_TUN:-tailscale0}"
TS_PORT="${TS_PORT:-41641}"

TAILSCALED_PID=""
SS_PID=""
SSHD_PID=""

shutdown() {
    info "shutting down..."
    [ -n "$SS_PID" ]         && kill -TERM "$SS_PID"         2>/dev/null || true
    [ -n "$SSHD_PID" ]       && kill -TERM "$SSHD_PID"       2>/dev/null || true
    [ -n "$TAILSCALED_PID" ] && kill -TERM "$TAILSCALED_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap shutdown TERM INT HUP

# ---------------------------------------------------------------------------
# tailscaled
# ---------------------------------------------------------------------------
ensure_tun() {
    # Kernel mode needs /dev/net/tun. If the host didn't pass --device, try to
    # create it (works when the container has mknod privileges); otherwise fall
    # back to userspace networking.
    if [ -c /dev/net/tun ]; then
        return 0
    fi
    warn "/dev/net/tun missing — attempting to create it"
    mkdir -p /dev/net
    if mknod /dev/net/tun c 10 200 2>/dev/null; then
        chmod 600 /dev/net/tun
        info "created /dev/net/tun"
        return 0
    fi
    warn "could not create /dev/net/tun — using userspace networking (SS -> tailnet routing degraded)"
    TS_TUN="userspace-networking"
    return 1
}

start_tailscaled() {
    ensure_tun
    mkdir -p "$TS_STATE_DIR" "$(dirname "$TS_SOCKET")"

    info "starting tailscaled (tun=$TS_TUN, port=$TS_PORT)..."
    tailscaled \
        --state="$TS_STATE_FILE" \
        --socket="$TS_SOCKET" \
        --tun="$TS_TUN" \
        --port="$TS_PORT" &
    TAILSCALED_PID=$!

    # Wait for the local API socket to come up.
    local waited=0
    while ! tailscale --socket="$TS_SOCKET" status >/dev/null 2>&1; do
        # `status` exits non-zero when logged out too; only bail if the daemon died.
        if ! kill -0 "$TAILSCALED_PID" 2>/dev/null; then
            error "tailscaled exited during startup"
        fi
        [ "$waited" -ge 30 ] && break
        sleep 1
        waited=$((waited + 1))
    done
    info "tailscaled is up (pid: $TAILSCALED_PID)"
}

tailscale_up() {
    # An auth key is required the first time; subsequent runs reuse the persisted
    # state file, so it becomes optional once the node is registered.
    if [ -z "${TS_AUTHKEY:-}" ] && [ ! -s "$TS_STATE_FILE" ]; then
        error "TS_AUTHKEY is required for first login (no state at $TS_STATE_FILE)"
    fi

    local args=(--socket="$TS_SOCKET" up)
    args+=(--accept-routes="${TS_ACCEPT_ROUTES:-true}")
    args+=(--accept-dns="${TS_ACCEPT_DNS:-false}")
    [ -n "${TS_AUTHKEY:-}" ]  && args+=(--authkey="$TS_AUTHKEY")
    [ -n "${TS_HOSTNAME:-}" ] && args+=(--hostname="$TS_HOSTNAME")
    [ -n "${TS_ROUTES:-}" ]   && args+=(--advertise-routes="$TS_ROUTES")
    [ "${TS_ADVERTISE_EXIT_NODE:-false}" = "true" ] && args+=(--advertise-exit-node)
    [ -n "${TS_EXIT_NODE:-}" ] && args+=(--exit-node="$TS_EXIT_NODE")

    # Advertising subnet routes / exit node requires IP forwarding.
    if [ -n "${TS_ROUTES:-}" ] || [ "${TS_ADVERTISE_EXIT_NODE:-false}" = "true" ]; then
        sysctl -w net.ipv4.ip_forward=1        >/dev/null 2>&1 || warn "could not enable ipv4 forwarding"
        sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true
    fi

    # shellcheck disable=SC2206
    [ -n "${TS_EXTRA_ARGS:-}" ] && args+=(${TS_EXTRA_ARGS})

    info "joining tailnet: tailscale up ${args[*]//--authkey=*/--authkey=***}"
    tailscale "${args[@]}" || error "tailscale up failed"

    local ip
    ip=$(tailscale --socket="$TS_SOCKET" ip -4 2>/dev/null | head -n1)
    info "tailnet node is up${ip:+ (tailscale IP: $ip)}"
}

# ---------------------------------------------------------------------------
# shadowsocks-rust (external entry point)
# ---------------------------------------------------------------------------
# Strip an inline "# comment" and surrounding whitespace. docker --env-file does
# NOT honor inline comments, so a value like "tcp_and_udp   # note" arrives
# literally; sanitize the constrained fields so a stray comment can't corrupt
# the generated config. (Not applied to SS_PASSWORD, which may contain '#'.)
_clean() {
    local v="${1%%#*}"                 # drop inline comment
    v="${v#"${v%%[![:space:]]*}"}"     # ltrim
    v="${v%"${v##*[![:space:]]}"}"     # rtrim
    printf '%s' "$v"
}

start_shadowsocks() {
    local port;   port="$(_clean "${SS_PORT:-8388}")"
    local method; method="$(_clean "${SS_METHOD:-chacha20-ietf-poly1305}")"
    local mode;   mode="$(_clean "${SS_MODE:-tcp_and_udp}")"
    local obfs;   obfs="$(_clean "${SS_OBFS:-http}")"
    local obfs_host; obfs_host="$(_clean "${SS_OBFS_HOST:-}")"
    local password="${SS_PASSWORD:-}"

    [ -z "$password" ] && {
        password="$(pwgen -ns 32 1 2>/dev/null || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
        warn "SS_PASSWORD not set, generated one: $password"
    }

    # Build the ss-server config with jq so it is valid JSON with or without the
    # obfs plugin. simple-obfs's server has no obfs-host flag — obfs-host is a
    # CLIENT setting, so we only pass obfs=<mode> here and log the host clients
    # should use.
    local config=/etc/shadowsocks/config.json
    local base
    base=$(jq -n \
        --argjson port "$port" \
        --arg password "$password" \
        --arg method "$method" \
        --arg mode "$mode" \
        '{server:"0.0.0.0", server_port:$port, password:$password, timeout:300,
          method:$method, mode:$mode, fast_open:false}')
    if [ "$obfs" != "none" ] && [ -n "$obfs" ]; then
        echo "$base" | jq --arg obfs "$obfs" \
            '. + {plugin:"obfs-server", plugin_opts:("obfs=" + $obfs)}' >"$config"
    else
        echo "$base" >"$config"
    fi

    info "shadowsocks config:"
    info "  server_port : $port"
    info "  password    : $password"
    info "  method      : $method"
    info "  mode        : $mode"
    if [ "$obfs" != "none" ] && [ -n "$obfs" ]; then
        info "  obfs        : $obfs  (clients set plugin_opts: obfs=${obfs}${obfs_host:+;obfs-host=$obfs_host})"
    else
        info "  obfs        : disabled"
    fi

    info "starting ss-server..."
    ss-server -c "$config" &
    SS_PID=$!
}

# ---------------------------------------------------------------------------
# Optional hardened SSH server (SSH_ENABLE=true) — same key-only + PerSource-
# Penalties hardening as the standalone `sshd` container. Reachable at the node's
# tailnet IP (100.x) and, if published, a host port. Runs in the background.
# ---------------------------------------------------------------------------
start_sshd() {
    local ssh_user="${SSH_USER:-dev}"
    local keys_dir=/etc/ssh/keys

    case "$ssh_user" in
        root|"" ) error "SSH_USER must be a non-root name (got '${ssh_user}')" ;;
        *[!a-z0-9_-]* ) error "SSH_USER '${ssh_user}' has invalid characters" ;;
    esac

    if ! id "$ssh_user" >/dev/null 2>&1; then
        info "creating ssh user '$ssh_user'"
        adduser -D -s /bin/bash "$ssh_user" || error "failed to create user $ssh_user"
        passwd -u "$ssh_user" >/dev/null 2>&1 || true
    fi
    if [ "${SSH_SUDO:-false}" = "true" ]; then
        echo "$ssh_user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$ssh_user"
        chmod 440 /etc/sudoers.d/"$ssh_user"
    fi

    # authorized_keys from env / mounted file / URL
    local home_dir ssh_dir auth_file
    home_dir="$(getent passwd "$ssh_user" | cut -d: -f6)"
    ssh_dir="${home_dir}/.ssh"; auth_file="${ssh_dir}/authorized_keys"
    mkdir -p "$ssh_dir"; : > "$auth_file"
    [ -n "${SSH_AUTHORIZED_KEYS:-}" ] && printf '%b\n' "$SSH_AUTHORIZED_KEYS" >> "$auth_file"
    [ -f /config/authorized_keys ]    && cat /config/authorized_keys >> "$auth_file"
    if [ -n "${SSH_AUTHORIZED_KEYS_URL:-}" ]; then
        curl -fsSL "$SSH_AUTHORIZED_KEYS_URL" >> "$auth_file" || warn "failed to fetch SSH_AUTHORIZED_KEYS_URL"
    fi
    sed -i '/^[[:space:]]*$/d' "$auth_file"
    if ! grep -qE '^(ssh-|ecdsa-|sk-)' "$auth_file"; then
        error "SSH_ENABLE=true but no valid public keys (set SSH_AUTHORIZED_KEYS, mount /config/authorized_keys, or set SSH_AUTHORIZED_KEYS_URL)"
    fi
    chmod 700 "$ssh_dir"; chmod 600 "$auth_file"; chown -R "$ssh_user":"$ssh_user" "$ssh_dir"

    # persistent host keys
    mkdir -p "$keys_dir"
    if ! ls "$keys_dir"/ssh_host_*_key >/dev/null 2>&1; then
        info "generating ssh host keys in $keys_dir"
        ssh-keygen -t ed25519 -f "$keys_dir/ssh_host_ed25519_key" -N '' -q
        ssh-keygen -t rsa -b 4096 -f "$keys_dir/ssh_host_rsa_key" -N '' -q
    fi
    chmod 600 "$keys_dir"/ssh_host_*_key
    chmod 644 "$keys_dir"/ssh_host_*_key.pub 2>/dev/null || true

    local config=/etc/ssh/sshd_config
    cat > "$config" <<EOF
Port ${SSH_PORT:-22}
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

HostKey ${keys_dir}/ssh_host_ed25519_key
HostKey ${keys_dir}/ssh_host_rsa_key

PubkeyAuthentication yes
AuthenticationMethods publickey
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
AllowUsers ${ssh_user}
AuthorizedKeysFile .ssh/authorized_keys

MaxAuthTries ${SSH_MAX_AUTH_TRIES:-3}
LoginGraceTime ${SSH_LOGIN_GRACE:-20}
PerSourcePenalties authfail:${SSH_PENALTY_AUTHFAIL:-20s} max:${SSH_PENALTY_MAX:-30m}
MaxStartups 10:30:60

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
    /usr/sbin/sshd -t -f "$config" || error "sshd config validation failed"

    info "SSH server enabled: user=$ssh_user port=${SSH_PORT:-22} (publickey only, MaxAuthTries=${SSH_MAX_AUTH_TRIES:-3})"
    ssh-keygen -lf "$keys_dir/ssh_host_ed25519_key.pub" 2>/dev/null | sed 's/^/[ssh] host key: /'
    /usr/sbin/sshd -D -e -f "$config" &
    SSHD_PID=$!
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
start_tailscaled
tailscale_up
start_shadowsocks
[ "${SSH_ENABLE:-false}" = "true" ] && start_sshd

# Supervise children; if any dies, tear everything down so Docker's restart
# policy brings the container back cleanly.
while true; do
    if ! kill -0 "$TAILSCALED_PID" 2>/dev/null; then
        warn "tailscaled exited"; break
    fi
    if ! kill -0 "$SS_PID" 2>/dev/null; then
        warn "ss-server exited"; break
    fi
    if [ -n "$SSHD_PID" ] && ! kill -0 "$SSHD_PID" 2>/dev/null; then
        warn "sshd exited"; break
    fi
    sleep 5
done

shutdown
exit 1
