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

echo "Restoring system network services..."
ip addr flush dev "$IFACE" || true
systemctl start NetworkManager || echo "Warning: Failed to restart NetworkManager."
echo "Restarting systemd-networkd..."
systemctl start systemd-networkd || echo "Warning: Failed to restart systemd-networkd."

if systemctl is-enabled --quiet systemd-resolved.service; then
  echo "Restarting systemd-resolved..."
  systemctl start systemd-resolved.service || echo "Warning: Failed to restart systemd-resolved."
fi

echo "Walled garden has been stopped."