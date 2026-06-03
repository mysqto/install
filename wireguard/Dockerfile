# WireGuard Testing Environment
FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install required packages
RUN apt-get update && apt-get install -y \
    # WireGuard and networking tools
    wireguard \
    wireguard-tools \
    iptables \
    iproute2 \
    iputils-ping \
    net-tools \
    # Development and testing tools  
    curl \
    wget \
    jq \
    qrencode \
    python3 \
    # Text processing tools
    gawk \
    grep \
    sed \
    coreutils \
    # System tools
    systemd \
    sudo \
    procps \
    # Debugging tools
    tcpdump \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Enable IP forwarding
RUN echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
RUN echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf

# Create test user
RUN useradd -m -s /bin/bash tester && \
    echo 'tester ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Create directories for WireGuard
RUN mkdir -p /etc/wireguard /etc/wireguard/keys /etc/wireguard/clients

# Set working directory
WORKDIR /app

# Copy scripts (will be mounted from host)
COPY . .

# Make scripts executable
RUN chmod +x install wg-client 2>/dev/null || true

# Create entrypoint script
RUN cat > /entrypoint.sh << 'EOF'
#!/bin/bash
set -e

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Load WireGuard module if available
modprobe wireguard 2>/dev/null || echo "WireGuard module not available (normal in some container environments)"

# Execute the command
exec "$@"
EOF

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
