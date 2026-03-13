#!/usr/bin/env bash
set -euo pipefail

# Walled garden iptables rules.
# Usage: iptables_rules.sh [apply|clear] [IFACE] [AP_IP]

ACTION="${1:-apply}"
IFACE="${2:-}"
AP_IP="${3:-10.42.0.1}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root" >&2
  exit 2
fi

if [ "$ACTION" = "clear" ]; then
  echo "Clearing walled garden iptables rules..."
  iptables -t nat -F 2>/dev/null || true
  iptables -F FORWARD 2>/dev/null || true
  iptables -P FORWARD ACCEPT 2>/dev/null || true
  echo "Done — iptables cleared."
  exit 0
fi

# Auto-detect interface if not provided
if [ -z "$IFACE" ]; then
  IFACE=$(ls /sys/class/net/ | grep -E '^wl' | head -1)
  if [ -z "$IFACE" ]; then
    echo "Error: No wireless interface found." >&2
    exit 1
  fi
fi

echo "Applying walled garden rules on $IFACE (portal: $AP_IP)..."

# Flush existing rules
iptables -t nat -F
iptables -F FORWARD

# Block all forwarding — clients cannot reach the internet
iptables -P FORWARD DROP

# Intercept ALL DNS traffic (UDP+TCP) and redirect to our dnsmasq
# This catches clients with hardcoded DNS (e.g. 8.8.8.8, Cloudflare, etc.)
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 53 \
  -j DNAT --to-destination "${AP_IP}:53"
iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport 53 \
  -j DNAT --to-destination "${AP_IP}:53"

# Redirect HTTP to captive portal
iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport 80 \
  -j DNAT --to-destination "${AP_IP}:80"

# Redirect HTTPS to captive portal (browsers will show cert warning)
iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport 443 \
  -j DNAT --to-destination "${AP_IP}:443"

echo "Done — walled garden iptables active."
