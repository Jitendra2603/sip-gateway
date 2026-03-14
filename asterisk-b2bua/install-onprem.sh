#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install Asterisk B2BUA SIP middleware on a non-GCP host.

Usage:
  sudo bash install-onprem.sh \
    --twilio-termination-host <trunk.pstn.twilio.com> \
    [--external-ip <public-ip>] \
    [--twilio-termination-port 5060] \
    [--twilio-username <user> --twilio-password <pass>] \
    [--eleven-allow-cidr <cidr>] \
    [--eleven-username <user> --eleven-password <pass>] \
    [--eleven-forward-host <host-or-ip> --eleven-forward-port 5060] \
    [--install-dir /opt/sip-middleware] \
    [--skip-firewall]

Examples:
  sudo bash install-onprem.sh \
    --twilio-termination-host "jitendra-test.pstn.twilio.com"

  sudo bash install-onprem.sh \
    --twilio-termination-host "jitendra-test.pstn.twilio.com" \
    --twilio-username "twilio-user" \
    --twilio-password "twilio-pass" \
    --eleven-allow-cidr "0.0.0.0/0" \
    --eleven-username "eleven-user" \
    --eleven-password "eleven-pass"
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (use sudo)." >&2
    exit 1
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    return
  fi

  if [[ -f /etc/debian_version ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") $(. /etc/os-release && echo "$VERSION_CODENAME") stable" >/etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif [[ -f /etc/redhat-release ]]; then
    if command -v dnf >/dev/null 2>&1; then
      dnf -y install dnf-plugins-core
      dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
      yum -y install yum-utils
      yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      yum -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
  else
    echo "Unsupported OS. Install Docker manually and retry." >&2
    exit 1
  fi

  systemctl enable docker
  systemctl start docker
}

open_firewall_ports() {
  if [[ "${SKIP_FIREWALL}" == "true" ]]; then
    return
  fi

  if command -v ufw >/dev/null 2>&1; then
    ufw allow 5060/tcp || true
    ufw allow 5061/tcp || true
    ufw allow 5060/udp || true
    ufw allow 10000:20000/udp || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=5060/tcp || true
    firewall-cmd --permanent --add-port=5061/tcp || true
    firewall-cmd --permanent --add-port=5060/udp || true
    firewall-cmd --permanent --add-port=10000-20000/udp || true
    firewall-cmd --reload || true
  fi
}

auto_detect_external_ip() {
  if [[ -n "${EXTERNAL_IP}" ]]; then
    return
  fi

  EXTERNAL_IP="$(curl -fsS https://ifconfig.me 2>/dev/null || true)"
  if [[ -z "${EXTERNAL_IP}" ]]; then
    EXTERNAL_IP="$(curl -fsS https://api.ipify.org 2>/dev/null || true)"
  fi
  if [[ -z "${EXTERNAL_IP}" ]]; then
    echo "Could not auto-detect external IP. Pass --external-ip." >&2
    exit 1
  fi
}

TWILIO_TERMINATION_HOST=""
TWILIO_TERMINATION_PORT="5060"
TWILIO_USERNAME=""
TWILIO_PASSWORD=""
ELEVEN_ALLOW_CIDR="0.0.0.0/0"
ELEVEN_USERNAME=""
ELEVEN_PASSWORD=""
ELEVEN_FORWARD_HOST=""
ELEVEN_FORWARD_PORT="5060"
EXTERNAL_IP=""
INSTALL_DIR="/opt/sip-middleware"
SKIP_FIREWALL="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --twilio-termination-host) TWILIO_TERMINATION_HOST="$2"; shift 2 ;;
    --twilio-termination-port) TWILIO_TERMINATION_PORT="$2"; shift 2 ;;
    --twilio-username) TWILIO_USERNAME="$2"; shift 2 ;;
    --twilio-password) TWILIO_PASSWORD="$2"; shift 2 ;;
    --eleven-allow-cidr) ELEVEN_ALLOW_CIDR="$2"; shift 2 ;;
    --eleven-username) ELEVEN_USERNAME="$2"; shift 2 ;;
    --eleven-password) ELEVEN_PASSWORD="$2"; shift 2 ;;
    --eleven-forward-host) ELEVEN_FORWARD_HOST="$2"; shift 2 ;;
    --eleven-forward-port) ELEVEN_FORWARD_PORT="$2"; shift 2 ;;
    --external-ip) EXTERNAL_IP="$2"; shift 2 ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --skip-firewall) SKIP_FIREWALL="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "${TWILIO_TERMINATION_HOST}" ]]; then
  echo "--twilio-termination-host is required." >&2
  usage
  exit 1
fi

if [[ -n "${TWILIO_USERNAME}" && -z "${TWILIO_PASSWORD}" ]]; then
  echo "If --twilio-username is set, --twilio-password is required." >&2
  exit 1
fi

if [[ -n "${TWILIO_PASSWORD}" && -z "${TWILIO_USERNAME}" ]]; then
  echo "If --twilio-password is set, --twilio-username is required." >&2
  exit 1
fi

if [[ -n "${ELEVEN_USERNAME}" && -z "${ELEVEN_PASSWORD}" ]]; then
  echo "If --eleven-username is set, --eleven-password is required." >&2
  exit 1
fi

if [[ -n "${ELEVEN_PASSWORD}" && -z "${ELEVEN_USERNAME}" ]]; then
  echo "If --eleven-password is set, --eleven-username is required." >&2
  exit 1
fi

require_root
auto_detect_external_ip
install_docker

CONFIG_DIR="${INSTALL_DIR}/asterisk"
ENV_FILE="${INSTALL_DIR}/onprem.env"
mkdir -p "${CONFIG_DIR}"

if [[ ! -f "${CONFIG_DIR}/modules.conf" ]]; then
  docker rm -f sip-middleware-seed >/dev/null 2>&1 || true
  docker create --name sip-middleware-seed andrius/asterisk:latest >/dev/null
  docker cp sip-middleware-seed:/etc/asterisk/. "${CONFIG_DIR}/"
  docker rm -f sip-middleware-seed >/dev/null 2>&1 || true
fi

cat >"${ENV_FILE}" <<EOF
EXTERNAL_IP=${EXTERNAL_IP}
TWILIO_TERMINATION_HOST=${TWILIO_TERMINATION_HOST}
TWILIO_TERMINATION_PORT=${TWILIO_TERMINATION_PORT}
TWILIO_USERNAME=${TWILIO_USERNAME}
TWILIO_PASSWORD=${TWILIO_PASSWORD}
ELEVEN_ALLOW_CIDR=${ELEVEN_ALLOW_CIDR}
ELEVEN_USERNAME=${ELEVEN_USERNAME}
ELEVEN_PASSWORD=${ELEVEN_PASSWORD}
ELEVEN_FORWARD_HOST=${ELEVEN_FORWARD_HOST}
ELEVEN_FORWARD_PORT=${ELEVEN_FORWARD_PORT}
EOF
chmod 600 "${ENV_FILE}"

cat >/usr/local/bin/render-sip-middleware-onprem.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

INSTALL_DIR="/opt/sip-middleware"
CONFIG_DIR="${INSTALL_DIR}/asterisk"
ENV_FILE="${INSTALL_DIR}/onprem.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file at ${ENV_FILE}" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

: "${EXTERNAL_IP:?EXTERNAL_IP is required}"
: "${TWILIO_TERMINATION_HOST:?TWILIO_TERMINATION_HOST is required}"
TWILIO_TERMINATION_PORT="${TWILIO_TERMINATION_PORT:-5060}"
ELEVEN_ALLOW_CIDR="${ELEVEN_ALLOW_CIDR:-0.0.0.0/0}"
ELEVEN_FORWARD_PORT="${ELEVEN_FORWARD_PORT:-5060}"

ELEVEN_INBOUND_AUTH_LINE=""
ELEVEN_AUTH_BLOCK=""
if [[ -n "${ELEVEN_USERNAME:-}" && -n "${ELEVEN_PASSWORD:-}" ]]; then
  ELEVEN_INBOUND_AUTH_LINE="auth=eleven-auth"
  ELEVEN_AUTH_BLOCK=$(cat <<AUTH
[eleven-auth]
type=auth
auth_type=userpass
username=${ELEVEN_USERNAME}
password=${ELEVEN_PASSWORD}
AUTH
)
fi

OUTBOUND_AUTH_LINE=""
AUTH_BLOCK=""
if [[ -n "${TWILIO_USERNAME:-}" && -n "${TWILIO_PASSWORD:-}" ]]; then
  OUTBOUND_AUTH_LINE="outbound_auth=twilio-auth"
  AUTH_BLOCK=$(cat <<AUTH
[twilio-auth]
type=auth
auth_type=userpass
username=${TWILIO_USERNAME}
password=${TWILIO_PASSWORD}
AUTH
)
fi

ELEVEN_FORWARD_PJSIP_BLOCK=""
FROM_TWILIO_DIALPLAN_BLOCK=$(cat <<'DIALPLAN'
[from-twilio]
exten => _X.,1,NoOp(Inbound from Twilio is not configured on this test middleware)
 same => n,Hangup(403)

exten => _+X.,1,NoOp(Inbound from Twilio is not configured on this test middleware)
 same => n,Hangup(403)

exten => s,1,NoOp(Inbound from Twilio default route)
 same => n,Hangup(403)
DIALPLAN
)

if [[ -n "${ELEVEN_FORWARD_HOST:-}" ]]; then
  ELEVEN_FORWARD_PJSIP_BLOCK=$(cat <<PJSIP
[eleven-forward-aor]
type=aor
contact=sip:${ELEVEN_FORWARD_HOST}:${ELEVEN_FORWARD_PORT}

[eleven-forward]
type=endpoint
transport=transport-udp
context=from-eleven
disallow=all
allow=ulaw,alaw,g722
allow_subscribe=no
direct_media=no
rtp_symmetric=yes
force_rport=yes
rewrite_contact=yes
aors=eleven-forward-aor
from_domain=${ELEVEN_FORWARD_HOST}
PJSIP
)

  FROM_TWILIO_DIALPLAN_BLOCK=$(cat <<'DIALPLAN'
[from-twilio]
exten => _+X.,1,NoOp(Forward +E164 call from Twilio to Eleven ${EXTEN})
 same => n,Dial(PJSIP/${EXTEN}@eleven-forward,90)
 same => n,Hangup()

exten => _X.,1,NoOp(Forward numeric call from Twilio to Eleven ${EXTEN})
 same => n,Dial(PJSIP/${EXTEN}@eleven-forward,90)
 same => n,Hangup()

exten => s,1,NoOp(Received INVITE from Twilio without a numeric user part)
 same => n,Hangup(404)
DIALPLAN
)
fi

cat >"${CONFIG_DIR}/pjsip.conf" <<EOF
; Auto-generated by render-sip-middleware-onprem.sh
[global]
type=global
user_agent=xi-sip-middleware
endpoint_identifier_order=ip,username,anonymous

[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0:5060
external_signaling_address=${EXTERNAL_IP}
external_media_address=${EXTERNAL_IP}
local_net=10.0.0.0/8
local_net=172.16.0.0/12
local_net=192.168.0.0/16

[transport-tcp]
type=transport
protocol=tcp
bind=0.0.0.0:5060
external_signaling_address=${EXTERNAL_IP}
external_media_address=${EXTERNAL_IP}
local_net=10.0.0.0/8
local_net=172.16.0.0/12
local_net=192.168.0.0/16

[from-eleven-aor]
type=aor
max_contacts=20

[from-eleven]
type=endpoint
transport=transport-tcp
context=from-eleven
disallow=all
allow=ulaw,alaw,g722
allow_subscribe=no
direct_media=no
rtp_symmetric=yes
force_rport=yes
rewrite_contact=yes
aors=from-eleven-aor
${ELEVEN_INBOUND_AUTH_LINE}

[from-eleven-identify]
type=identify
endpoint=from-eleven
match=${ELEVEN_ALLOW_CIDR}

[twilio-trunk-aor]
type=aor
contact=sip:${TWILIO_TERMINATION_HOST}:${TWILIO_TERMINATION_PORT};transport=tcp

[twilio-trunk]
type=endpoint
transport=transport-tcp
context=from-twilio
disallow=all
allow=ulaw,alaw
allow_subscribe=no
direct_media=no
rtp_symmetric=yes
force_rport=yes
rewrite_contact=yes
aors=twilio-trunk-aor
from_domain=${TWILIO_TERMINATION_HOST}
${OUTBOUND_AUTH_LINE}

${AUTH_BLOCK}

${ELEVEN_AUTH_BLOCK}

${ELEVEN_FORWARD_PJSIP_BLOCK}
EOF

cat >"${CONFIG_DIR}/extensions.conf" <<'EOF'
; Auto-generated by render-sip-middleware-onprem.sh
[general]
static=yes
writeprotect=no
clearglobalvars=no

[from-eleven]
exten => _+X.,1,NoOp(Forward +E164 call from Eleven to Twilio ${EXTEN})
 same => n,Dial(PJSIP/${EXTEN}@twilio-trunk,90)
 same => n,Hangup()

exten => _X.,1,NoOp(Forward numeric call from Eleven to Twilio ${EXTEN})
 same => n,Dial(PJSIP/${EXTEN}@twilio-trunk,90)
 same => n,Hangup()

exten => s,1,NoOp(Received INVITE without a numeric user part)
 same => n,Hangup(404)
EOF

printf "\n%s\n" "${FROM_TWILIO_DIALPLAN_BLOCK}" >>"${CONFIG_DIR}/extensions.conf"

cat >"${CONFIG_DIR}/rtp.conf" <<'EOF'
; Auto-generated by render-sip-middleware-onprem.sh
[general]
rtpstart=10000
rtpend=20000
strictrtp=no
icesupport=no
EOF
SCRIPT
chmod +x /usr/local/bin/render-sip-middleware-onprem.sh

cat >/etc/systemd/system/sip-middleware.service <<'UNIT'
[Unit]
Description=SIP middleware Asterisk container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/usr/bin/docker rm -f sip-middleware
ExecStart=/usr/bin/docker run --detach --name sip-middleware --network host --restart unless-stopped --volume /opt/sip-middleware/asterisk:/etc/asterisk andrius/asterisk:latest
ExecStop=/usr/bin/docker stop sip-middleware
ExecStopPost=-/usr/bin/docker rm -f sip-middleware

[Install]
WantedBy=multi-user.target
UNIT

cat >/etc/systemd/system/sip-middleware-render.service <<'UNIT'
[Unit]
Description=Render SIP middleware config from /opt/sip-middleware/onprem.env
After=network-online.target sip-middleware.service
Wants=network-online.target
Requires=sip-middleware.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/render-sip-middleware-onprem.sh
ExecStartPost=/usr/bin/docker restart sip-middleware

[Install]
WantedBy=multi-user.target
UNIT

/usr/local/bin/render-sip-middleware-onprem.sh
systemctl daemon-reload
systemctl enable sip-middleware.service
systemctl start sip-middleware.service
systemctl enable sip-middleware-render.service
systemctl start sip-middleware-render.service
open_firewall_ports

echo
echo "Asterisk B2BUA middleware is up."
echo "External IP: ${EXTERNAL_IP}"
echo "Config file: ${ENV_FILE}"
echo
echo "Useful commands:"
echo "  sudo systemctl start sip-middleware-render.service"
echo "  sudo docker exec sip-middleware asterisk -rx 'pjsip show endpoints'"
echo "  sudo docker logs -f sip-middleware"
