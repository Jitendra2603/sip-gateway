#!/bin/bash
# GCE startup script — runs on first boot (Ubuntu 24.04 LTS).
# Installs Docker, detects the external IP, and prepares for deployment.
set -euo pipefail

LOG_FILE="/var/log/sip-gateway-startup.log"
INSTALL_DIR="/opt/sip-gateway"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== SIP Gateway startup $(date) ==="

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    apt-get update -y
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    echo "Docker installed: $(docker --version)"
fi

# Detect external IP from GCE metadata
EXTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)

INTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)

echo "Detected external IP: $EXTERNAL_IP"
echo "Detected internal IP: $INTERNAL_IP"

mkdir -p "$INSTALL_DIR/docker"

ENV_FILE="$INSTALL_DIR/docker/.env"
if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" <<EOF
EXTERNAL_IP=$EXTERNAL_IP
INTERNAL_IP=$INTERNAL_IP
CUSTOMER_SBC_ADDRESS=REPLACE_ME
CUSTOMER_SBC_PORT=5060
AUTH_USER=
AUTH_PASSWORD=
AUTH_REALM=
EOF
    echo "Created .env template at $ENV_FILE — operator must set CUSTOMER_SBC_ADDRESS"
fi

sed -i "s/^EXTERNAL_IP=.*/EXTERNAL_IP=$EXTERNAL_IP/" "$ENV_FILE"
sed -i "s/^INTERNAL_IP=.*/INTERNAL_IP=$INTERNAL_IP/" "$ENV_FILE"

echo "=== Startup complete ==="
echo "Deploy the docker-compose stack to $INSTALL_DIR using scripts/deploy.sh"
