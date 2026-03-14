#!/bin/bash
##
## On-prem / bare-metal / non-GCP install script for the SIP Gateway.
##
## Run this on any Linux host (Ubuntu 22.04+, Debian 12+) with a public IP.
## It installs Docker, clones the gateway config, and starts the stack.
##
## Usage:
##   curl -sSL <raw-url-to-this-script> | bash -s -- \
##       --external-ip <PUBLIC_IP> \
##       --internal-ip <PRIVATE_IP> \
##       --customer-sbc <SBC_ADDRESS> \
##       [--customer-sbc-port 5060] \
##       [--auth-user <user> --auth-password <pass>]
##
## If --internal-ip is the same as --external-ip (no NAT), just pass
## the same value for both.
##
set -euo pipefail

EXTERNAL_IP=""
INTERNAL_IP=""
CUSTOMER_SBC_ADDRESS=""
CUSTOMER_SBC_PORT="5060"
AUTH_USER=""
AUTH_PASSWORD=""
INSTALL_DIR="/opt/sip-gateway"

while [[ $# -gt 0 ]]; do
    case $1 in
        --external-ip)       EXTERNAL_IP="$2"; shift 2 ;;
        --internal-ip)       INTERNAL_IP="$2"; shift 2 ;;
        --customer-sbc)      CUSTOMER_SBC_ADDRESS="$2"; shift 2 ;;
        --customer-sbc-port) CUSTOMER_SBC_PORT="$2"; shift 2 ;;
        --auth-user)         AUTH_USER="$2"; shift 2 ;;
        --auth-password)     AUTH_PASSWORD="$2"; shift 2 ;;
        --install-dir)       INSTALL_DIR="$2"; shift 2 ;;
        *)                   echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Validation ---

if [ -z "$EXTERNAL_IP" ]; then
    echo "Attempting to auto-detect public IP..."
    EXTERNAL_IP=$(curl -s -4 https://ifconfig.me || curl -s -4 https://api.ipify.org || echo "")
    if [ -z "$EXTERNAL_IP" ]; then
        echo "Error: Could not auto-detect public IP. Pass --external-ip <IP>"
        exit 1
    fi
    echo "  Detected: $EXTERNAL_IP"
fi

if [ -z "$INTERNAL_IP" ]; then
    INTERNAL_IP=$(hostname -I | awk '{print $1}')
    echo "  Internal IP (auto): $INTERNAL_IP"
fi

if [ -z "$CUSTOMER_SBC_ADDRESS" ]; then
    echo "Error: --customer-sbc <address> is required"
    exit 1
fi

if { [ -n "$AUTH_USER" ] && [ -z "$AUTH_PASSWORD" ]; } || { [ -z "$AUTH_USER" ] && [ -n "$AUTH_PASSWORD" ]; }; then
    echo "Error: --auth-user and --auth-password must both be set or both empty"
    exit 1
fi

echo ""
echo "=== SIP Gateway On-Prem Install ==="
echo "  External IP:  $EXTERNAL_IP"
echo "  Internal IP:  $INTERNAL_IP"
echo "  Customer SBC: $CUSTOMER_SBC_ADDRESS:$CUSTOMER_SBC_PORT"
echo "  Install dir:  $INSTALL_DIR"
[ -n "$AUTH_USER" ] && echo "  Auth:         $AUTH_USER / ****"
[ -n "$AUTH_USER" ] && echo "  Auth:         $AUTH_USER / ****"
echo ""

# --- Install Docker if missing ---

if ! command -v docker &> /dev/null; then
    echo ">>> Installing Docker..."
    if [ -f /etc/debian_version ]; then
        apt-get update -y
        apt-get install -y ca-certificates curl
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    elif [ -f /etc/redhat-release ]; then
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        echo "Error: Unsupported OS. Install Docker manually, then re-run."
        exit 1
    fi
    systemctl enable docker && systemctl start docker
    echo "  Docker installed: $(docker --version)"
else
    echo ">>> Docker already installed: $(docker --version)"
fi

# --- Create directory structure ---

echo ">>> Setting up $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR/docker/kamailio" "$INSTALL_DIR/docker/rtpengine"

# --- Write Kamailio config ---

cat > "$INSTALL_DIR/docker/kamailio/kamailio.cfg" << 'KAMCFG'
#!KAMAILIO

debug=2
log_stderror=yes
memdbg=5
memlog=5
log_facility=LOG_LOCAL0

fork=yes
children=4

listen=udp:0.0.0.0:5060 advertise __EXTERNAL_IP__:5060
listen=tcp:0.0.0.0:5060 advertise __EXTERNAL_IP__:5060

tcp_connection_lifetime=3605
tcp_max_connections=2048

auto_aliases=no
dns=yes
rev_dns=no
dns_try_ipv6=no
dns_cache_init=on
use_dns_cache=on
dns_cache_flags=0

server_header="Server: ElevenLabs-SIP-GW"
user_agent_header="User-Agent: ElevenLabs-SIP-GW"

loadmodule "kex.so"
loadmodule "corex.so"
loadmodule "tm.so"
loadmodule "tmx.so"
loadmodule "sl.so"
loadmodule "rr.so"
loadmodule "pv.so"
loadmodule "maxfwd.so"
loadmodule "textops.so"
loadmodule "siputils.so"
loadmodule "xlog.so"
loadmodule "sanity.so"
loadmodule "nathelper.so"
loadmodule "rtpengine.so"
loadmodule "sdpops.so"
loadmodule "auth.so"

modparam("tm", "failure_reply_mode", 3)
modparam("tm", "fr_timer", 30000)
modparam("tm", "fr_inv_timer", 120000)
modparam("tm", "restart_fr_on_each_reply", 1)
modparam("tm", "auto_inv_100_reason", "Trying")

modparam("rr", "enable_full_lr", 1)
modparam("rr", "append_fromtag", 1)

modparam("rtpengine", "rtpengine_sock", "udp:127.0.0.1:22222")
modparam("rtpengine", "rtpengine_tout_ms", 5000)

modparam("nathelper", "received_avp", "$avp(RECEIVED)")

modparam("auth", "nonce_expire", 300)
modparam("auth", "nonce_count", 1)

request_route {
    xlog("L_INFO", "[$ci] $rm from $fu to $ru (src $si:$sp)\n");

    if (!mf_process_maxfwd_header("10")) {
        sl_send_reply("483", "Too Many Hops");
        exit;
    }

    if (!sanity_check("17895", "7")) {
        xlog("L_WARN", "[$ci] Malformed SIP message from $si:$sp\n");
        exit;
    }

    force_rport();

    if (is_method("OPTIONS") && uri == myself) {
        sl_send_reply("200", "OK");
        exit;
    }

    if (is_method("CANCEL")) {
        if (t_check_trans()) {
            route(RELAY);
        }
        exit;
    }

    if (has_totag()) {
        if (loose_route()) {
            if (is_method("INVITE|UPDATE")) {
                route(RTPMANAGE);
            } else if (is_method("ACK")) {
                if (t_check_trans()) {
                    route(RTPMANAGE);
                }
            } else if (is_method("BYE")) {
                rtpengine_delete();
            }
            route(RELAY);
            exit;
        }

        if (is_method("ACK")) {
            if (t_check_trans()) {
                route(RELAY);
                exit;
            } else {
                exit;
            }
        }

        sl_send_reply("404", "Not Found");
        exit;
    }

    if (is_method("INVITE")) {
        #!ifdef WITH_AUTH
        route(AUTH);
        #!endif

        record_route();
        route(RTPMANAGE);
        $ru = "sip:" + $rU + "@__CUSTOMER_SBC_ADDRESS__:__CUSTOMER_SBC_PORT__";
        xlog("L_INFO", "[$ci] Routing INVITE to $ru\n");
        t_on_failure("INVITE_FAILURE");
        t_on_reply("MANAGE_REPLY");
        route(RELAY);
        exit;
    }

    if (is_method("REGISTER")) {
        sl_send_reply("403", "Forbidden");
        exit;
    }

    route(RELAY);
}

route[AUTH] {
    if (!pv_auth_check("__AUTH_REALM__", "__AUTH_PASSWORD__", 0, 0)) {
        auth_challenge("__AUTH_REALM__", 1);
        xlog("L_WARN", "[$ci] Auth challenged/failed from $si:$sp (user=$au)\n");
        exit;
    }
    if ($au != "__AUTH_USER__") {
        xlog("L_WARN", "[$ci] Auth rejected: wrong username '$au' from $si:$sp\n");
        sl_send_reply("403", "Forbidden");
        exit;
    }
    xlog("L_INFO", "[$ci] Auth OK for user $au from $si:$sp\n");
    consume_credentials();
}

route[RELAY] {
    if (!t_relay()) {
        xlog("L_ERR", "[$ci] Relay failed for $rm\n");
        sl_reply_error();
    }
}

route[RTPMANAGE] {
    if (has_body("application/sdp")) {
        rtpengine_manage("replace-origin replace-session-connection RTP/AVP");
    }
}

onreply_route[MANAGE_REPLY] {
    xlog("L_INFO", "[$ci] Reply $rs $rr\n");
    if (has_body("application/sdp")) {
        rtpengine_manage("replace-origin replace-session-connection RTP/AVP");
    }
}

failure_route[INVITE_FAILURE] {
    xlog("L_WARN", "[$ci] INVITE failed with $T_reply_code $T_reply_reason\n");
    if (t_is_canceled()) { exit; }
    rtpengine_delete();
}
KAMCFG


# --- Write entrypoint ---

cat > "$INSTALL_DIR/docker/kamailio/entrypoint.sh" << 'ENTRY'
#!/bin/sh
set -e
REALM="${AUTH_REALM:-${EXTERNAL_IP}}"
SAFE_AUTH_USER="${AUTH_USER:-_disabled_}"
SAFE_AUTH_PASSWORD="${AUTH_PASSWORD:-_disabled_}"
AUTH_DEFINE=""
if [ -n "$AUTH_USER" ] && [ "$AUTH_USER" != "" ]; then
    AUTH_DEFINE="#!define WITH_AUTH"
fi
{ echo "$AUTH_DEFINE"; cat /etc/kamailio/kamailio.cfg.template; } | sed \
    -e "s/__EXTERNAL_IP__/${EXTERNAL_IP}/g" \
    -e "s/__CUSTOMER_SBC_ADDRESS__/${CUSTOMER_SBC_ADDRESS}/g" \
    -e "s/__CUSTOMER_SBC_PORT__/${CUSTOMER_SBC_PORT:-5060}/g" \
    -e "s/__AUTH_USER__/${SAFE_AUTH_USER}/g" \
    -e "s/__AUTH_PASSWORD__/${SAFE_AUTH_PASSWORD}/g" \
    -e "s/__AUTH_REALM__/${REALM}/g" \
    > /etc/kamailio/kamailio.cfg
echo "=== Kamailio config generated ==="
echo "  EXTERNAL_IP:          ${EXTERNAL_IP}"
echo "  CUSTOMER_SBC_ADDRESS: ${CUSTOMER_SBC_ADDRESS}"
echo "  CUSTOMER_SBC_PORT:    ${CUSTOMER_SBC_PORT:-5060}"
exec kamailio -DD -E -m 256
ENTRY
chmod +x "$INSTALL_DIR/docker/kamailio/entrypoint.sh"

# --- Write Dockerfiles ---

cat > "$INSTALL_DIR/docker/kamailio/Dockerfile" << 'DOCKF'
FROM ghcr.io/kamailio/kamailio-ci:5.8
COPY kamailio.cfg /etc/kamailio/kamailio.cfg.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 5060/udp 5060/tcp 5061/tcp
ENTRYPOINT ["/entrypoint.sh"]
DOCKF

cat > "$INSTALL_DIR/docker/rtpengine/Dockerfile" << 'DOCKF'
FROM debian:bookworm-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends rtpengine iptables && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/spool/rtpengine
EXPOSE 22222/udp 10000-20000/udp
ENTRYPOINT ["rtpengine"]
CMD ["--foreground", "--log-stderr"]
DOCKF

# --- Write docker-compose ---

cat > "$INSTALL_DIR/docker/docker-compose.yml" << 'COMPOSE'
services:
  kamailio:
    build:
      context: ./kamailio
    container_name: sip-gateway-kamailio
    network_mode: host
    restart: unless-stopped
    environment:
      - EXTERNAL_IP=${EXTERNAL_IP}
      - CUSTOMER_SBC_ADDRESS=${CUSTOMER_SBC_ADDRESS}
      - CUSTOMER_SBC_PORT=${CUSTOMER_SBC_PORT:-5060}
      - AUTH_USER=${AUTH_USER}
      - AUTH_PASSWORD=${AUTH_PASSWORD}
      - AUTH_REALM=${AUTH_REALM:-${EXTERNAL_IP}}
    depends_on:
      rtpengine:
        condition: service_started
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"

  rtpengine:
    build:
      context: ./rtpengine
    container_name: sip-gateway-rtpengine
    network_mode: host
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_NICE
    command:
      - "--foreground"
      - "--log-stderr"
      - "--table=-1"
      - "--interface=pub/${INTERNAL_IP}!${EXTERNAL_IP}"
      - "--listen-ng=127.0.0.1:22222"
      - "--port-min=10000"
      - "--port-max=20000"
      - "--log-level=6"
      - "--delete-delay=0"
      - "--timeout=60"
      - "--silent-timeout=600"
      - "--final-timeout=7200"
      - "--tos=184"
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
COMPOSE

# --- Write .env ---

cat > "$INSTALL_DIR/docker/.env" <<EOF
EXTERNAL_IP=$EXTERNAL_IP
INTERNAL_IP=$INTERNAL_IP
CUSTOMER_SBC_ADDRESS=$CUSTOMER_SBC_ADDRESS
CUSTOMER_SBC_PORT=$CUSTOMER_SBC_PORT
AUTH_USER=$AUTH_USER
AUTH_PASSWORD=$AUTH_PASSWORD
AUTH_REALM=$EXTERNAL_IP
EOF

# --- Open firewall (if ufw/firewalld present) ---

echo ">>> Configuring firewall..."
if command -v ufw &> /dev/null; then
    ufw allow 5060/tcp comment "SIP TCP"
    ufw allow 5060/udp comment "SIP UDP"
    ufw allow 10000:20000/udp comment "RTP media"
    echo "  ufw rules added"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=5060/tcp
    firewall-cmd --permanent --add-port=5060/udp
    firewall-cmd --permanent --add-port=10000-20000/udp
    firewall-cmd --reload
    echo "  firewalld rules added"
else
    echo "  No ufw/firewalld detected. Ensure ports 5060/tcp, 5060/udp, 10000-20000/udp are open."
fi

# --- Build and start ---

echo ">>> Building Docker images..."
cd "$INSTALL_DIR/docker"
docker compose --env-file .env build

echo ">>> Starting SIP Gateway..."
docker compose --env-file .env up -d

sleep 4

echo ""
echo "=== SIP Gateway is running ==="
echo ""
echo "  External IP: $EXTERNAL_IP"
echo "  SIP URI:     sip:$EXTERNAL_IP:5060;transport=tcp"
echo "  Forwards to: $CUSTOMER_SBC_ADDRESS:$CUSTOMER_SBC_PORT"
echo ""
echo "  Status: docker compose -f $INSTALL_DIR/docker/docker-compose.yml ps"
echo "  Logs:   docker compose -f $INSTALL_DIR/docker/docker-compose.yml logs -f"
echo ""
echo "Configure your ElevenLabs outbound trunk:"
echo "  address:   $EXTERNAL_IP"
echo "  transport: TCP"
[ -n "$AUTH_USER" ] && echo "  authUsername: $AUTH_USER" && echo "  authPassword: ****"
echo ""
echo "If behind NAT, ensure your router/firewall forwards:"
echo "  TCP 5060        -> $INTERNAL_IP:5060"
echo "  UDP 5060        -> $INTERNAL_IP:5060"
echo "  UDP 10000-20000 -> $INTERNAL_IP:10000-20000"
