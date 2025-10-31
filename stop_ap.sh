#!/usr/bin/env bash
set -euo pipefail

# Script to stop the walled garden and restore normal network operations.
# Must be run as root.

IFACE="wlp3s0"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo)." >&2
  exit 2
fi

echo "Stopping services..."
pkill hostapd || true
pkill dnsmasq || true
pkill -f "python3 -m http.server" || true

echo "Clearing firewall rules..."
SCRIPT_DIR="$(dirname "$0")"
"$SCRIPT_DIR/iptables_rules.sh" clear

echo "Restoring NetworkManager control over $IFACE..."
ip addr flush dev "$IFACE" || true
nmcli dev set "$IFACE" managed yes

echo "Walled garden has been stopped."