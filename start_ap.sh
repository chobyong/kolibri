#!/usr/bin/env bash
set -euo pipefail

# Simple helper to configure the wireless interface, start hostapd/dnsmasq
# and run a local web server for the captive portal.

IFACE="wlp3s0"
AP_IP="192.168.50.1/24"
PORTAL_IP="192.168.50.1"
SSID="HIM-GUATE02"
PASSPHRASE="1234567890"
ROOT_DIR="$(dirname "$0")/www"
# We'll generate hostapd config at runtime so SSID matches hostname
HOSTAPD_CONF="$(dirname "$0")/hostapd.conf"
DNSMASQ_CONF="$(dirname "$0")/dnsmasq.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo)." >&2
  exit 2
fi

# Check for required commands
for cmd in hostapd dnsmasq ip sysctl; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: Required command '$cmd' not found. Please install it." >&2
    exit 1
  fi
done

echo "Disabling NetworkManager for $IFACE to prevent conflicts"
# Tell NetworkManager to ignore the interface so it doesn't interfere with hostapd.
nmcli dev set "$IFACE" managed no || echo "Warning: Failed to set interface as unmanaged. This might cause conflicts."

echo "Bringing interface $IFACE up and assigning $AP_IP"
ip link set "$IFACE" down || true
ip addr flush dev "$IFACE" || true
ip addr add "$AP_IP" dev "$IFACE"
ip link set "$IFACE" up

echo "Enabling IPv4 forwarding"
sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "Stopping any existing hostapd/dnsmasq instances"
pkill hostapd || true
pkill dnsmasq || true

echo "Generating hostapd config with SSID: $SSID"
cat > "$HOSTAPD_CONF" <<EOF
interface=$IFACE
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=6
ieee80211n=1
auth_algs=1
wpa=2
wpa_passphrase=${PASSPHRASE}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

echo "Waiting for interface to be ready..."
# Add a short delay to allow the interface to initialize before starting hostapd
sleep 1

echo "Starting hostapd"
hostapd -B "$HOSTAPD_CONF"

echo "Starting dnsmasq"
# Run dnsmasq with our config file
# Use --port=0 to disable the DNS server functionality, as systemd-resolved may be using the port.
dnsmasq --conf-file="$DNSMASQ_CONF" --port=0

echo "Starting local web server on port 80"
# Use python http.server; systemd unit may be preferable for production
cd "$ROOT_DIR"
nohup python3 -m http.server 80 --bind 0.0.0.0 >/dev/null 2>&1 &

echo "Starting education content server on port 8080"
# IMPORTANT: Make sure this directory exists and contains your content.
EDUCATION_DIR="/home/him/education_content"
if [ ! -d "$EDUCATION_DIR" ]; then
  echo "Warning: Education content directory not found. Creating '$EDUCATION_DIR'."
  mkdir -p "$EDUCATION_DIR"
fi
cd "$EDUCATION_DIR"
nohup python3 -m http.server 8080 --bind 0.0.0.0 >/dev/null 2>&1 &

echo "Applying iptables NAT/redirect rules (HTTP and HTTPS -> portal)"
# Call the dedicated script to apply firewall rules.
SCRIPT_DIR="$(dirname "$0")"
"$SCRIPT_DIR/iptables_rules.sh" apply

echo "Walled garden should be running. Connect to SSID '${SSID}' with password '${PASSPHRASE}'."
