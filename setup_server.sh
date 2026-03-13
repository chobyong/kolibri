#!/usr/bin/env bash
set -euo pipefail

# HIM Education Server — Automated Setup
#
# This script installs all dependencies and configures the system to run
# the walled garden captive portal. DHCP and DNS are managed by NetworkManager.
#
# Prerequisites:
#   1. Debian/Ubuntu with NetworkManager installed
#   2. A wireless interface available
#   3. Run as: sudo ./setup_server.sh

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run with sudo: sudo ./setup_server.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================="
echo "  HIM Education Server Setup"
echo "========================================="
echo ""

# --- Step 1: System configuration ---
echo "### Step 1: System Configuration ###"
echo "Disabling power saving (suspend, hibernate)..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
echo ""

# --- Step 2: Install required packages ---
echo "### Step 2: Installing Required Packages ###"
apt-get update
apt-get install -y iptables python3 openssl
echo ""

# --- Step 3: Ensure NetworkManager is running ---
echo "### Step 3: Verifying NetworkManager ###"
if ! systemctl is-active --quiet NetworkManager; then
  echo "Starting NetworkManager..."
  systemctl enable --now NetworkManager
fi
echo "NetworkManager is active."

# Verify a wireless interface exists
IFACE=$(nmcli -t -f TYPE,DEVICE device | grep '^wifi:' | head -1 | cut -d: -f2)
if [ -z "$IFACE" ]; then
  echo "WARNING: No wireless interface detected. The hotspot won't work without one."
else
  echo "Wireless interface found: $IFACE"
fi
echo ""

# --- Step 4: Kolibri installation (optional) ---
echo "### Step 4: Kolibri Installation ###"
KOLIBRI_DEB=$(find "$SCRIPT_DIR" -maxdepth 1 -name "kolibri*installer-debian*.deb" 2>/dev/null | head -n 1)
if [ -n "$KOLIBRI_DEB" ]; then
  echo "Found Kolibri installer: $KOLIBRI_DEB"
  dpkg -i "$KOLIBRI_DEB" || true
  apt-get install -f -y
  echo "Kolibri installed. Run first-time setup to create user and import content."
else
  echo "No Kolibri .deb found in $SCRIPT_DIR — skipping."
  echo "Download from https://learningequality.org/kolibri/download/ and re-run if needed."
fi
echo ""

# --- Step 5: Make scripts executable ---
echo "### Step 5: Setting Permissions ###"
chmod +x "$SCRIPT_DIR/start_ap.sh" "$SCRIPT_DIR/stop_ap.sh" "$SCRIPT_DIR/iptables_rules.sh" "$SCRIPT_DIR/server.py"
echo ""

# --- Step 6: Install systemd services ---
echo "### Step 6: Installing Systemd Services ###"
for svc in him-ap.service him-firewall.service him-webserver.service walled-garden.service; do
  cp "$SCRIPT_DIR/$svc" /etc/systemd/system/
done
systemctl daemon-reload
echo "Systemd services installed."
echo ""

echo "========================================="
echo "  Setup Complete!"
echo "========================================="
echo ""
echo "Quick start (manual):   sudo ./start_ap.sh"
echo "Quick stop:             sudo ./stop_ap.sh"
echo ""
echo "Enable on boot:         sudo systemctl enable him-ap him-firewall him-webserver"
echo "  or all-in-one:        sudo systemctl enable walled-garden"
echo ""
echo "Services:"
echo "  Captive Portal:  http://10.42.0.1/"
echo "  Kolibri:         http://10.42.0.1:8080/"
echo "  NextCloud:       http://10.42.0.1:8081/"
echo ""
echo "SSID: him-edu  |  Password: 1234567890"