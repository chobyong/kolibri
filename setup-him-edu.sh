#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
#  HIM Education — Bootstrap Setup Script
# =============================================================================
#  Downloads and installs the full HIM Education server to /opt/him-edu.
#
#  Usage:
#    curl -fsSL -o /tmp/setup-him-edu.sh https://raw.githubusercontent.com/chobyong/kolibri/main/setup-him-edu.sh
#    chmod +x /tmp/setup-him-edu.sh
#    sudo /tmp/setup-him-edu.sh
# =============================================================================

INSTALL_DIR="/opt/him-edu"
REPO_URL="https://github.com/chobyong/kolibri.git"

log()  { echo -e "\n\033[1;34m>>>\033[0m $*"; }
ok()   { echo -e "  \033[1;32m✓\033[0m $*"; }
err()  { echo -e "  \033[1;31m✗\033[0m $*" >&2; }

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run with sudo:  sudo $0"
  exit 1
fi

echo ""
echo "============================================================"
echo "     HIM Education — Bootstrap Setup"
echo "============================================================"
echo "  Repository: $REPO_URL"
echo "  Install to: $INSTALL_DIR"
echo "============================================================"

# --- Install git if missing --------------------------------------------------
log "Checking prerequisites..."
apt-get update -qq
for pkg in git curl; do
  if ! command -v "$pkg" >/dev/null 2>&1; then
    apt-get install -y "$pkg"
    ok "$pkg installed"
  else
    ok "$pkg already installed"
  fi
done

# --- Clean and clone ---------------------------------------------------------
log "Preparing $INSTALL_DIR..."
if [ -d "$INSTALL_DIR" ]; then
  echo "  Removing existing $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR"
  ok "Old installation removed"
fi

log "Cloning repository..."
git clone "$REPO_URL" "$INSTALL_DIR"
ok "Repository cloned to $INSTALL_DIR"

# --- Run the master installer ------------------------------------------------
log "Running install.sh..."
cd "$INSTALL_DIR"
chmod +x install.sh
./install.sh

# --- Start and enable --------------------------------------------------------
log "Starting walled garden..."
chmod +x start_ap.sh
./start_ap.sh
ok "Walled garden started"

systemctl enable walled-garden 2>/dev/null || true
ok "Walled garden enabled on boot"

echo ""
echo "============================================================"
echo "     Setup Complete!"
echo "============================================================"
echo "  Project installed at: $INSTALL_DIR"
echo "  Wi-Fi SSID: him-edu  Password: 1234567890"
echo "  Landing page: http://10.42.0.1/"
echo "  Kolibri:      http://10.42.0.1:8080/"
echo "  NextCloud:    http://10.42.0.1:8081/"
echo "============================================================"
