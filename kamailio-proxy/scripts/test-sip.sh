#!/bin/bash
##
## Quick smoke test for the SIP gateway using SIP OPTIONS.
## Requires: sipsak (brew install sipsak / apt install sipsak)
##
## Usage:
##   ./test-sip.sh <gateway-ip> [port]
##
set -euo pipefail

GATEWAY_IP="${1:?Usage: ./test-sip.sh <gateway-ip> [port]}"
GATEWAY_PORT="${2:-5060}"

echo "=== SIP Gateway Smoke Test ==="
echo "  Target: $GATEWAY_IP:$GATEWAY_PORT"
echo ""

if ! command -v sipsak &> /dev/null; then
    echo "sipsak not found. Install with:"
    echo "  macOS: brew install sipsak"
    echo "  Linux: apt install sipsak"
    echo ""
    echo "Falling back to netcat UDP probe..."
    echo -ne "OPTIONS sip:test@$GATEWAY_IP:$GATEWAY_PORT SIP/2.0\r\nVia: SIP/2.0/UDP 127.0.0.1:5060;branch=z9hG4bK-test\r\nFrom: <sip:test@127.0.0.1>;tag=test123\r\nTo: <sip:test@$GATEWAY_IP>\r\nCall-ID: test-$(date +%s)@127.0.0.1\r\nCSeq: 1 OPTIONS\r\nMax-Forwards: 70\r\nContent-Length: 0\r\n\r\n" | nc -u -w 3 "$GATEWAY_IP" "$GATEWAY_PORT"
    exit $?
fi

echo "Sending SIP OPTIONS..."
sipsak -s "sip:test@$GATEWAY_IP:$GATEWAY_PORT" -v

echo ""
echo "If you see a 200 OK, the SIP signaling layer is healthy."
