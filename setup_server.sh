#!/usr/bin/env bash
set -euo pipefail

# This script automates the complete setup of the HIM Education Server.
# It should be run with sudo from within the cloned repository directory.
#
# Before running:
# 1. A user 'him' should exist.
# 2. This script should be run as: sudo ./setup_server.sh
# 3. The Kolibri .deb installer file must be placed in this directory.

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run with sudo: sudo ./setup_server.sh" >&2
  exit 1
fi

echo "### Step 1: System Configuration ###"

# Disable Power Saving
echo "Disabling power saving (suspend, hibernate)..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
echo "Power saving disabled."
echo

echo "### Step 2: Installing Required Packages ###"
echo "Updating package lists..."
apt-get update

echo "Installing required packages: hostapd, dnsmasq, iptables..."
apt-get install -y hostapd dnsmasq iptables
echo "Required packages installed."
echo

echo "### Step 3: Kolibri Installation ###"

# Find the Kolibri .deb file in the current directory
KOLIBRI_DEB=$(find . -maxdepth 1 -name "kolibri*installer-debian*.deb" | head -n 1)

if [ -z "$KOLIBRI_DEB" ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!!! ERROR: Kolibri installer not found."
    echo "!!! Please download the Kolibri .deb file from:"
    echo "!!! https://learningequality.org/kolibri/download/"
    echo "!!! and place it in this directory before running the script."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
fi

echo "Found Kolibri installer: $KOLIBRI_DEB"
echo "Installing Kolibri..."
dpkg -i "$KOLIBRI_DEB"

# Fix any missing dependencies from the Kolibri installation
apt-get install -f -y
echo "Kolibri has been installed."
echo "You will need to perform the first-time setup (create user, import content)."
echo

echo "### Step 4: Walled Garden Finalization ###"

echo "Stopping default services..."
systemctl stop hostapd || true
systemctl stop dnsmasq || true

echo "Making scripts executable..."
chmod +x ./start_ap.sh ./stop_ap.sh ./iptables_rules.sh

echo
echo "################################################"
echo "###              Setup Complete!             ###"
echo "################################################"
echo "You can now run 'sudo ./start_ap.sh' to start the walled garden."
echo "Or, to have it start on boot, run 'sudo systemctl enable ./walled-garden.service'."