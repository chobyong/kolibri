#!/usr/bin/env bash
set -euo pipefail

# Stop the HIM Education walled garden and restore normal networking.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo)." >&2
  exit 2
fi

# Auto-detect wireless interface
IFACE=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -1)
if [ -z "$IFACE" ]; then
  IFACE=$(ls /sys/class/net/ | grep -E '^wl' | head -1)
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
"$SCRIPT_DIR/iptables_rules.sh" clear

echo "Restoring interface to NetworkManager..."
if [ -n "$IFACE" ]; then
  ip addr flush dev "$IFACE" 2>/dev/null || true
  nmcli device set "$IFACE" managed yes 2>/dev/null || true
fi

echo "Walled garden stopped."