#!/bin/sh
set -e

REALM="${AUTH_REALM:-${EXTERNAL_IP}}"
# Kamailio validates pv_auth_check params at load time even for unreachable routes.
# Use placeholder values when auth is not configured to prevent parse errors.
SAFE_AUTH_USER="${AUTH_USER:-_disabled_}"
SAFE_AUTH_PASSWORD="${AUTH_PASSWORD:-_disabled_}"

sed \
    -e "s/__EXTERNAL_IP__/${EXTERNAL_IP}/g" \
    -e "s/__CUSTOMER_SBC_ADDRESS__/${CUSTOMER_SBC_ADDRESS}/g" \
    -e "s/__CUSTOMER_SBC_PORT__/${CUSTOMER_SBC_PORT:-5060}/g" \
    -e "s/__AUTH_USER__/${SAFE_AUTH_USER}/g" \
    -e "s/__AUTH_PASSWORD__/${SAFE_AUTH_PASSWORD}/g" \
    -e "s/__AUTH_REALM__/${REALM}/g" \
    /etc/kamailio/kamailio.cfg.template > /etc/kamailio/kamailio.cfg

echo "=== Kamailio config generated ==="
echo "  EXTERNAL_IP:           ${EXTERNAL_IP}"
echo "  CUSTOMER_SBC_ADDRESS:  ${CUSTOMER_SBC_ADDRESS}"
echo "  CUSTOMER_SBC_PORT:     ${CUSTOMER_SBC_PORT:-5060}"
echo "  AUTH_USER:             ${AUTH_USER}"
echo "  AUTH_REALM:            ${REALM}"

exec kamailio -DD -E -m 256
