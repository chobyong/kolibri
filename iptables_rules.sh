#!/usr/bin/env bash
set -euo pipefail

# Script to apply/clear iptables rules used by the walled garden.
# Run as root.

ACTION=${1:-apply}
IFACE="wlp3s0"
PORTAL_IP="192.168.50.1"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root" >&2
  exit 2
fi

if [ "$ACTION" = "clear" ]; then
  echo "Clearing NAT/forwarding rules"
  iptables -t nat -F || true
  iptables -F || true
  exit 0
fi

echo "Applying NAT/redirect rules"
iptables -t nat -F
iptables -F FORWARD

# Allow access to the education content server on port 8080
iptables -A FORWARD -i "$IFACE" -p tcp --dport 8080 -d "$PORTAL_IP" -j ACCEPT

# Redirect all other HTTP/HTTPS traffic to the portal page
iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport 80 -j DNAT --to-destination "${PORTAL_IP}:80"
iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport 443 -j REDIRECT --to-ports 80

echo "Done"
