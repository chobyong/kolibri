#!/usr/bin/env bash
set -euo pipefail

SSID="him-edu"
PASSPHRASE="1234567890"
AP_IP="10.42.0.1"
DHCP_RANGE="10.42.0.10,10.42.0.254,255.255.255.0,12h"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOSTAPD_CONF="${SCRIPT_DIR}/hostapd.conf"
DNSMASQ_CONF="${SCRIPT_DIR}/dnsmasq.conf"
IFACE="wlx00c0cabb67ce"
DISABLED_IFACE="wlp1s0"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo)." >&2
  exit 2
fi

echo "Disabling internal Wi-Fi card ($DISABLED_IFACE)..."
nmcli device set "$DISABLED_IFACE" managed no 2>/dev/null || true
ip link set "$DISABLED_IFACE" down 2>/dev/null || true

echo "Cleaning up previous instances..."
pkill hostapd 2>/dev/null || true
pkill dnsmasq 2>/dev/null || true
pkill -f "python3 ${SCRIPT_DIR}/server.py" 2>/dev/null || true
sleep 1

echo "Removing $IFACE from NetworkManager..."
nmcli device set "$IFACE" managed no 2>/dev/null || true
sleep 1

echo "Configuring interface $IFACE with IP ${AP_IP}/24..."
ip link set "$IFACE" down 2>/dev/null || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "${AP_IP}/24" dev "$IFACE"
ip link set "$IFACE" up
sleep 1

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

echo "Starting hostapd..."
hostapd -B "$HOSTAPD_CONF"
sleep 2

echo "Starting dnsmasq (DHCP + DNS)..."
dnsmasq --conf-file="$DNSMASQ_CONF" --pid-file=/run/him-dnsmasq.pid
echo "dnsmasq started (PID $(cat /run/him-dnsmasq.pid))"

echo "Applying iptables walled garden rules..."
"$SCRIPT_DIR/iptables_rules.sh" apply "$IFACE" "$AP_IP"

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
