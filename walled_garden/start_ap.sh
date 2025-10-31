#!/usr/bin/env bash
set -euo pipefail

# Simple helper to configure the wireless interface, start hostapd/dnsmasq
# and run a local web server for the captive portal.

IFACE="wlp3s0"
AP_IP="10.42.0.1/24"
PORTAL_IP="10.42.0.1"
SSID=$(hostname)
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

echo "Verifying network interface $IFACE exists..."
if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
    echo "!!! ERROR: Network interface '$IFACE' not found." >&2
    echo "!!! Please check the IFACE variable in this script and ensure" >&2
    echo "!!! your wireless hardware is enabled." >&2
    echo "!!! You can list available interfaces with 'ip addr'." >&2
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
    exit 1
fi

echo "Stopping conflicting network services..."
systemctl stop NetworkManager || echo "Warning: Failed to stop NetworkManager."
systemctl stop systemd-networkd || echo "Warning: Failed to stop systemd-networkd."
systemctl stop dnsmasq.service || true

if systemctl is-active --quiet systemd-resolved.service; then
  echo "Stopping systemd-resolved to free up DNS port 53"
  systemctl stop systemd-resolved.service
fi

echo "Stopping any lingering hostapd/dnsmasq instances..."
pkill hostapd || true
pkill dnsmasq || true
sleep 1 # Give processes a moment to fully terminate and release ports

echo "Bringing interface $IFACE up and assigning $AP_IP"
ip link set "$IFACE" down || true
ip addr flush dev "$IFACE" || true
ip addr add "$AP_IP" dev "$IFACE"
ip link set "$IFACE" up
echo "Enabling IPv4 forwarding"
sysctl -w net.ipv4.ip_forward=1 >/dev/null

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
rsn_pairwise=CCMP
EOF

echo "Waiting for interface to be ready..."
# Add a short delay to allow the interface to initialize before starting hostapd
sleep 1

echo "Starting hostapd"
hostapd -B "$HOSTAPD_CONF"

echo "Generating dnsmasq config"
cat > "$DNSMASQ_CONF" <<EOF
interface=$IFACE
dhcp-range=10.42.0.10,10.42.0.254,255.255.255.0,12h
dhcp-option=3,$PORTAL_IP
dhcp-option=6,$PORTAL_IP
address=/#/$PORTAL_IP
EOF

echo "Starting dnsmasq"
# Run dnsmasq with our config file
# The 'address' option above creates a DNS wildcard that resolves all domains
# to our portal IP, which is key for a captive portal.
dnsmasq --conf-file="$DNSMASQ_CONF"

echo "Verifying DHCP/DNS service..."
if ! pgrep -x "dnsmasq" > /dev/null; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
    echo "!!! ERROR: dnsmasq (DHCP/DNS server) failed to start." >&2
    echo "!!! Port 67 (DHCP) is likely still in use." >&2
    echo "!!! Run 'sudo lsof -i :67' to identify the conflicting process." >&2
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
    exit 1
fi

echo "Applying iptables NAT/redirect rules (HTTP and HTTPS -> portal)"
# Call the dedicated script to apply firewall rules.
SCRIPT_DIR="$(dirname "$0")"
"$SCRIPT_DIR/iptables_rules.sh" apply

echo "Starting local web server on port 80"
# Use python http.server; systemd unit may be preferable for production
cd "$ROOT_DIR"
nohup python3 -m http.server 80 --bind 0.0.0.0 >/dev/null 2>&1 &

echo "Walled garden should be running. Connect to SSID '${SSID}' with password '${PASSPHRASE}'."
