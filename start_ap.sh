#!/usr/bin/env bash
set -euo pipefail

# Start the HIM Education walled garden.
# Uses hostapd for AP, dnsmasq for DHCP/DNS, iptables for walled garden,
# and a Python captive portal server on port 80/443.

SSID="him-edu"
PASSPHRASE="1234567890"
AP_IP="10.42.0.1"
DHCP_RANGE="10.42.0.10,10.42.0.254,255.255.255.0,12h"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOSTAPD_CONF="${SCRIPT_DIR}/hostapd.conf"
DNSMASQ_CONF="${SCRIPT_DIR}/dnsmasq.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo)." >&2
  exit 2
fi

# Auto-detect wireless interface
IFACE=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -1)
if [ -z "$IFACE" ]; then
  IFACE=$(ls /sys/class/net/ | grep -E '^wl' | head -1)
fi
if [ -z "$IFACE" ]; then
  echo "Error: No wireless interface found." >&2
  exit 1
fi
echo "Using wireless interface: $IFACE"

# Stop any previous instances
echo "Cleaning up previous instances..."
pkill hostapd 2>/dev/null || true
pkill dnsmasq 2>/dev/null || true
pkill -f "python3 ${SCRIPT_DIR}/server.py" 2>/dev/null || true
sleep 1

# Tell NetworkManager to leave this interface alone
echo "Removing interface from NetworkManager..."
nmcli device set "$IFACE" managed no 2>/dev/null || true
sleep 1

# Configure the wireless interface
echo "Configuring interface $IFACE with IP ${AP_IP}/24..."
ip link set "$IFACE" down 2>/dev/null || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "${AP_IP}/24" dev "$IFACE"
ip link set "$IFACE" up
sleep 1

# Generate hostapd config
echo "Generating hostapd config (SSID: $SSID)..."
cat > "$HOSTAPD_CONF" <<EOF
interface=${IFACE}
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

# Generate dnsmasq config
echo "Generating dnsmasq config..."
cat > "$DNSMASQ_CONF" <<EOF
# HIM Education dnsmasq — DHCP + DNS
interface=${IFACE}
bind-interfaces
except-interface=lo
listen-address=${AP_IP}
dhcp-range=${DHCP_RANGE}
dhcp-option=3,${AP_IP}
dhcp-option=6,${AP_IP}
# Redirect ALL DNS to portal IP (walled garden)
address=/#/${AP_IP}
log-queries
log-dhcp
EOF

# Start hostapd
echo "Starting hostapd..."
hostapd -B "$HOSTAPD_CONF"
sleep 2

# Start dnsmasq (DHCP + DNS)
echo "Starting dnsmasq (DHCP + DNS)..."
dnsmasq --conf-file="$DNSMASQ_CONF" --pid-file=/run/him-dnsmasq.pid
echo "dnsmasq started (PID $(cat /run/him-dnsmasq.pid))"

# Apply walled garden firewall rules
echo "Applying iptables walled garden rules..."
"$SCRIPT_DIR/iptables_rules.sh" apply "$IFACE" "$AP_IP"

# Start the captive portal web server
if ! pgrep -f "python3 ${SCRIPT_DIR}/server.py" >/dev/null 2>&1; then
  echo "Starting captive portal web server..."
  nohup python3 "$SCRIPT_DIR/server.py" >"$SCRIPT_DIR/server.log" 2>&1 &
fi

echo ""
echo "========================================="
echo "  HIM Education Walled Garden is ACTIVE"
echo "========================================="
echo "  SSID:      $SSID"
echo "  Password:  $PASSPHRASE"
echo "  Portal:    http://${AP_IP}/"
echo "  Kolibri:   http://${AP_IP}:8080/"
echo "  NextCloud: http://${AP_IP}:8081/"
echo "  Interface: $IFACE"
echo "========================================="
