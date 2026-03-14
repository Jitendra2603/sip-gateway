#!/bin/bash
##
## Deploy (or update) the SIP gateway Docker Compose stack to a GCE instance.
##
## Usage:
##   ./deploy.sh --customer-sbc <address> [--customer-sbc-port <port>]
##               [--auth-user <user> --auth-password <pass>]
##               [--project <id>] [--zone <zone>] [--instance <name>]
##
## Prerequisites:
##   - gcloud CLI authenticated
##   - VM already exists (via terraform or manual gcloud create)
##
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_ID="${GCP_PROJECT:-your-gcp-project}"
ZONE="${GCP_ZONE:-europe-west1-b}"
INSTANCE="${INSTANCE_NAME:-sip-gateway}"
CUSTOMER_SBC_ADDRESS=""
CUSTOMER_SBC_PORT="5060"
AUTH_USER=""
AUTH_PASSWORD=""
USE_IAP="--tunnel-through-iap"

while [[ $# -gt 0 ]]; do
    case $1 in
        --customer-sbc)      CUSTOMER_SBC_ADDRESS="$2"; shift 2 ;;
        --customer-sbc-port) CUSTOMER_SBC_PORT="$2"; shift 2 ;;
        --auth-user)         AUTH_USER="$2"; shift 2 ;;
        --auth-password)     AUTH_PASSWORD="$2"; shift 2 ;;
        --project)           PROJECT_ID="$2"; shift 2 ;;
        --zone)              ZONE="$2"; shift 2 ;;
        --instance)          INSTANCE="$2"; shift 2 ;;
        --no-iap)            USE_IAP=""; shift ;;
        *)                   echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$CUSTOMER_SBC_ADDRESS" ]; then
    echo "Error: --customer-sbc <address> is required"
    echo ""
    echo "Usage: ./deploy.sh --customer-sbc sbc.customer.com [options]"
    echo ""
    echo "Options:"
    echo "  --customer-sbc-port <port>    SBC SIP port (default: 5060)"
    echo "  --auth-user <user>            Digest auth username (optional)"
    echo "  --auth-password <pass>        Digest auth password (optional)"
    echo "  --project <id>                GCP project (default: your-gcp-project)"
    echo "  --zone <zone>                 GCP zone (default: europe-west1-b)"
    echo "  --instance <name>             VM name (default: sip-gateway)"
    echo "  --no-iap                      SSH directly instead of IAP tunnel"
    exit 1
fi

REGION="$(echo "$ZONE" | sed 's/-[a-z]$//')"

echo "=== Deploying SIP Gateway ==="
echo "  Project:  $PROJECT_ID"
echo "  Zone:     $ZONE"
echo "  Instance: $INSTANCE"
echo "  SBC:      $CUSTOMER_SBC_ADDRESS:$CUSTOMER_SBC_PORT"
[ -n "$AUTH_USER" ] && echo "  Auth:     $AUTH_USER / ****"
echo ""

EXTERNAL_IP=$(gcloud compute addresses describe "${INSTANCE}-ip" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --format='get(address)' 2>/dev/null || echo "")

if [ -z "$EXTERNAL_IP" ]; then
    echo "Error: Could not find static IP '${INSTANCE}-ip'. Create it first."
    exit 1
fi

echo "  Static IP: $EXTERNAL_IP"

# Auto-detect internal IP from the VM
INTERNAL_IP=$(gcloud compute instances describe "$INSTANCE" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --format='get(networkInterfaces[0].networkIP)' 2>/dev/null || echo "")

if [ -z "$INTERNAL_IP" ]; then
    echo "Error: Could not detect internal IP for $INSTANCE."
    exit 1
fi

echo "  Internal IP: $INTERNAL_IP"
echo ""

REMOTE_DIR="/opt/sip-gateway"

echo ">>> Copying docker files to instance..."
gcloud compute scp --recurse $USE_IAP \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    "$PROJECT_ROOT/docker/" \
    "$INSTANCE:$REMOTE_DIR/"

echo ">>> Configuring .env..."
gcloud compute ssh "$INSTANCE" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    $USE_IAP \
    --command="sudo bash -c 'cat > $REMOTE_DIR/docker/.env <<EOF
EXTERNAL_IP=$EXTERNAL_IP
INTERNAL_IP=$INTERNAL_IP
CUSTOMER_SBC_ADDRESS=$CUSTOMER_SBC_ADDRESS
CUSTOMER_SBC_PORT=$CUSTOMER_SBC_PORT
AUTH_USER=$AUTH_USER
AUTH_PASSWORD=$AUTH_PASSWORD
AUTH_REALM=${EXTERNAL_IP}
EOF'"

echo ">>> Building and starting Docker Compose stack..."
gcloud compute ssh "$INSTANCE" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    $USE_IAP \
    --command="cd $REMOTE_DIR/docker && sudo docker compose --env-file .env build && sudo docker compose --env-file .env up -d"

echo ""
echo "=== Deployment complete ==="
echo ""
echo "SIP Gateway running at $EXTERNAL_IP"
echo ""
echo "ElevenLabs outbound trunk config:"
echo "  address:   $EXTERNAL_IP"
echo "  transport: TCP"
[ -n "$AUTH_USER" ] && echo "  authUsername: $AUTH_USER"
[ -n "$AUTH_PASSWORD" ] && echo "  authPassword: ****"
echo ""
echo "Commands:"
echo "  Status: gcloud compute ssh $INSTANCE --project=$PROJECT_ID --zone=$ZONE $USE_IAP --command='sudo docker compose -f $REMOTE_DIR/docker/docker-compose.yml ps'"
echo "  Logs:   gcloud compute ssh $INSTANCE --project=$PROJECT_ID --zone=$ZONE $USE_IAP --command='sudo docker compose -f $REMOTE_DIR/docker/docker-compose.yml logs -f'"
