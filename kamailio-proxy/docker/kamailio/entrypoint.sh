#!/bin/sh
set -e

REALM="${AUTH_REALM:-${EXTERNAL_IP}}"
SAFE_AUTH_USER="${AUTH_USER:-_disabled_}"
SAFE_AUTH_PASSWORD="${AUTH_PASSWORD:-_disabled_}"

# If AUTH_USER is set, enable digest auth by injecting the preprocessor define
AUTH_DEFINE=""
if [ -n "$AUTH_USER" ] && [ "$AUTH_USER" != "" ]; then
    AUTH_DEFINE="#!define WITH_AUTH"
    echo "  Auth:    ENABLED (user=$AUTH_USER)"
else
    echo "  Auth:    DISABLED"
fi

# Inject WITH_AUTH define at top of config if needed, then substitute placeholders
{
    echo "$AUTH_DEFINE"
    cat /etc/kamailio/kamailio.cfg.template
} | sed \
    -e "s/__EXTERNAL_IP__/${EXTERNAL_IP}/g" \
    -e "s/__CUSTOMER_SBC_ADDRESS__/${CUSTOMER_SBC_ADDRESS}/g" \
    -e "s/__CUSTOMER_SBC_PORT__/${CUSTOMER_SBC_PORT:-5060}/g" \
    -e "s/__AUTH_USER__/${SAFE_AUTH_USER}/g" \
    -e "s/__AUTH_PASSWORD__/${SAFE_AUTH_PASSWORD}/g" \
    -e "s/__AUTH_REALM__/${REALM}/g" \
    > /etc/kamailio/kamailio.cfg

echo "=== Kamailio config generated ==="
echo "  EXTERNAL_IP:           ${EXTERNAL_IP}"
echo "  CUSTOMER_SBC_ADDRESS:  ${CUSTOMER_SBC_ADDRESS}"
echo "  CUSTOMER_SBC_PORT:     ${CUSTOMER_SBC_PORT:-5060}"

exec kamailio -DD -E -m 256
