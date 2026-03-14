#!/bin/bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-xi-playground}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-f}"
INSTANCE_NAME="${INSTANCE_NAME:-xi-sip-middleware-1}"
ADDRESS_NAME="${ADDRESS_NAME:-xi-sip-middleware-ip}"
FIREWALL_RULE_NAME="${FIREWALL_RULE_NAME:-xi-sip-middleware-ingress}"
NETWORK="${NETWORK:-default}"
NETWORK_TAG="${NETWORK_TAG:-xi-sip-middleware}"
STARTUP_SCRIPT_PATH="${STARTUP_SCRIPT_PATH:-$(pwd)/tmp/sip-middleware/startup-script.sh}"

TWILIO_TERMINATION_HOST="${TWILIO_TERMINATION_HOST:-replace-me.pstn.twilio.com}"
TWILIO_TERMINATION_PORT="${TWILIO_TERMINATION_PORT:-5060}"
TWILIO_USERNAME="${TWILIO_USERNAME:-}"
TWILIO_PASSWORD="${TWILIO_PASSWORD:-}"
ELEVEN_ALLOW_CIDR="${ELEVEN_ALLOW_CIDR:-127.0.0.1/32}"
ELEVEN_USERNAME="${ELEVEN_USERNAME:-}"
ELEVEN_PASSWORD="${ELEVEN_PASSWORD:-}"
ELEVEN_FORWARD_HOST="${ELEVEN_FORWARD_HOST:-}"
ELEVEN_FORWARD_PORT="${ELEVEN_FORWARD_PORT:-5060}"

if [[ ! -f "${STARTUP_SCRIPT_PATH}" ]]; then
  echo "Startup script not found at: ${STARTUP_SCRIPT_PATH}" >&2
  exit 1
fi

echo "Using project: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}" >/dev/null

if ! gcloud compute addresses describe "${ADDRESS_NAME}" --region "${REGION}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud compute addresses create "${ADDRESS_NAME}" \
    --project "${PROJECT_ID}" \
    --region "${REGION}"
fi

MIDDLEWARE_IP="$(gcloud compute addresses describe "${ADDRESS_NAME}" --region "${REGION}" --project "${PROJECT_ID}" --format="value(address)")"

if ! gcloud compute firewall-rules describe "${FIREWALL_RULE_NAME}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud compute firewall-rules create "${FIREWALL_RULE_NAME}" \
    --project "${PROJECT_ID}" \
    --network "${NETWORK}" \
    --direction INGRESS \
    --priority 1000 \
    --action ALLOW \
    --target-tags "${NETWORK_TAG}" \
    --source-ranges "0.0.0.0/0" \
    --rules "tcp:5060,tcp:5061,udp:5060,udp:10000-20000"
fi

if ! gcloud compute instances describe "${INSTANCE_NAME}" --zone "${ZONE}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud compute instances create "${INSTANCE_NAME}" \
    --project "${PROJECT_ID}" \
    --zone "${ZONE}" \
    --machine-type "e2-standard-2" \
    --tags "${NETWORK_TAG}" \
    --address "${MIDDLEWARE_IP}" \
    --image-family "debian-12" \
    --image-project "debian-cloud" \
    --metadata-from-file "startup-script=${STARTUP_SCRIPT_PATH}" \
    --metadata "twilio_termination_host=${TWILIO_TERMINATION_HOST},twilio_termination_port=${TWILIO_TERMINATION_PORT},twilio_username=${TWILIO_USERNAME},twilio_password=${TWILIO_PASSWORD},eleven_allow_cidr=${ELEVEN_ALLOW_CIDR},eleven_username=${ELEVEN_USERNAME},eleven_password=${ELEVEN_PASSWORD},eleven_forward_host=${ELEVEN_FORWARD_HOST},eleven_forward_port=${ELEVEN_FORWARD_PORT}"
else
  gcloud compute instances add-metadata "${INSTANCE_NAME}" \
    --project "${PROJECT_ID}" \
    --zone "${ZONE}" \
    --metadata "twilio_termination_host=${TWILIO_TERMINATION_HOST},twilio_termination_port=${TWILIO_TERMINATION_PORT},twilio_username=${TWILIO_USERNAME},twilio_password=${TWILIO_PASSWORD},eleven_allow_cidr=${ELEVEN_ALLOW_CIDR},eleven_username=${ELEVEN_USERNAME},eleven_password=${ELEVEN_PASSWORD},eleven_forward_host=${ELEVEN_FORWARD_HOST},eleven_forward_port=${ELEVEN_FORWARD_PORT}"

  gcloud compute ssh "${INSTANCE_NAME}" \
    --project "${PROJECT_ID}" \
    --zone "${ZONE}" \
    --command "sudo systemctl start sip-middleware-render.service"
fi

echo
echo "Middleware IP: ${MIDDLEWARE_IP}"
echo "Instance: ${INSTANCE_NAME}"
echo "Zone: ${ZONE}"
