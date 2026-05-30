#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IFACE="wlx00c0cabb67ce"
DISABLED_IFACE="wlp1s0"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo)." >&2
  exit 2
fi

echo "Stopping captive portal web server..."
pkill -f "python3 ${SCRIPT_DIR}/server.py" || true

echo "Stopping hostapd..."
pkill hostapd || true

echo "Stopping dnsmasq..."
if [ -f /run/him-dnsmasq.pid ]; then
  kill "$(cat /run/him-dnsmasq.pid)" 2>/dev/null || true
  rm -f /run/him-dnsmasq.pid
else
  pkill dnsmasq 2>/dev/null || true
fi

echo "Clearing iptables walled garden rules..."
"$SCRIPT_DIR/iptables_rules.sh" clear "$IFACE"

echo "Restoring $IFACE to NetworkManager..."
ip addr flush dev "$IFACE" 2>/dev/null || true
nmcli device set "$IFACE" managed yes 2>/dev/null || true

echo "Re-enabling internal Wi-Fi card ($DISABLED_IFACE)..."
nmcli device set "$DISABLED_IFACE" managed yes 2>/dev/null || true
ip link set "$DISABLED_IFACE" up 2>/dev/null || true

echo "Walled garden stopped."
