#!/usr/bin/env bash
set -euo pipefail

SSID="him-edu"
PASSPHRASE="1234567890"
AP_IP="10.42.0.1"
DHCP_RANGE="10.42.0.10,10.42.0.254,255.255.255.0,12h"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOSTAPD_CONF="${SCRIPT_DIR}/hostapd.conf"
DNSMASQ_CONF="${SCRIPT_DIR}/dnsmasq.conf"
# Auto-detect wireless interface — prefer USB adapter over PCIe/internal.
_pick_wifi_iface() {
  local _usb="" _fallback=""
  for _sys in /sys/class/net/*/wireless; do
    [ -d "$_sys" ] || continue
    local _if; _if=$(basename "$(dirname "$_sys")")
    _fallback="${_fallback:-$_if}"
    readlink -f "/sys/class/net/$_if/device" 2>/dev/null | grep -q "/usb" && _usb="$_if"
  done
  echo "${_usb:-$_fallback}"
}
IFACE="$(_pick_wifi_iface)"
if [ -z "$IFACE" ]; then
  echo "ERROR: No wireless interface found." >&2
  exit 1
fi
echo "Detected Wi-Fi interface: $IFACE"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (sudo)." >&2
  exit 2
fi

echo "Setting regulatory domain to US..."
iw reg set US 2>/dev/null || true

for _other_sys in /sys/class/net/*/wireless; do
  [ -d "$_other_sys" ] || continue
  _other=$(basename "$(dirname "$_other_sys")")
  [ "$_other" = "$IFACE" ] && continue
  echo "Disabling competing Wi-Fi interface: $_other..."
  nmcli device set "$_other" managed no 2>/dev/null || true
  ip link set "$_other" down 2>/dev/null || true
done

echo "Cleaning up previous instances..."
pkill hostapd 2>/dev/null || true
pkill dnsmasq 2>/dev/null || true
pkill -f "python3 ${SCRIPT_DIR}/server.py" 2>/dev/null || true
sleep 1

echo "Removing $IFACE from NetworkManager..."
nmcli device set "$IFACE" managed no 2>/dev/null || true
sleep 1

echo "Resetting $IFACE to DOWN/managed so hostapd owns AP setup..."
ip link set "$IFACE" down 2>/dev/null || true
ip addr flush dev "$IFACE" 2>/dev/null || true

echo "Generating hostapd config (SSID: $SSID)..."
cat > "$HOSTAPD_CONF" <<EOF
interface=${IFACE}
driver=nl80211
country_code=US
ieee80211d=1
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

echo "Starting hostapd (in background, detached)..."
nohup hostapd "$HOSTAPD_CONF" > /tmp/hostapd-him.log 2>&1 &
disown $!

echo "Waiting for AP to come up (COUNTRY_UPDATE takes ~10s)..."
for i in $(seq 1 30); do
  if ip link show "$IFACE" 2>/dev/null | grep -q "state UP"; then break; fi
  sleep 1
done
if ! ip link show "$IFACE" 2>/dev/null | grep -q "state UP"; then
  echo "ERROR: AP interface did not come up within 30s"
  cat /tmp/hostapd-him.log
  exit 1
fi

echo "AP is up — assigning IP ${AP_IP}/24..."
ip addr add "${AP_IP}/24" dev "$IFACE" 2>/dev/null || true

pkill dnsmasq 2>/dev/null || true
sleep 1
echo "Starting dnsmasq (DHCP + DNS)..."
dnsmasq --conf-file="$DNSMASQ_CONF" --pid-file=/run/him-dnsmasq.pid
echo "dnsmasq started (PID $(cat /run/him-dnsmasq.pid))"

echo "Applying iptables walled garden rules..."
"$SCRIPT_DIR/iptables_rules.sh" apply "$IFACE" "$AP_IP"

if ! pgrep -f "python3 ${SCRIPT_DIR}/server.py" >/dev/null 2>&1; then
  echo "Starting captive portal web server..."
  nohup python3 "$SCRIPT_DIR/server.py" >"$SCRIPT_DIR/server.log" 2>&1 &
  disown $!
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
echo "=========================================="

# Keep this process alive so systemd tracks the service CGroup.
# All child processes (hostapd, dnsmasq, server.py) live until
# systemd stops this service (which kills the CGroup).
exec sleep infinity
