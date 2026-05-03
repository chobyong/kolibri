#!/usr/bin/env bash
# =============================================================================
#  HIM Education — Service Status Check
#  Run this script to quickly diagnose the state of all components.
#  Usage: sudo bash check-status.sh
# =============================================================================

SEP="──────────────────────────────────────────"

ok()   { echo -e "  \033[1;32m✓\033[0m $*"; }
warn() { echo -e "  \033[1;33m!\033[0m $*"; }
err()  { echo -e "  \033[1;31m✗\033[0m $*"; }
hdr()  { echo -e "\n\033[1;34m>>> $*\033[0m\n$SEP"; }

hdr "Wi-Fi Access Point (hostapd)"
if pgrep -x hostapd > /dev/null; then
  ok "hostapd running (PID: $(pgrep -x hostapd))"
  sudo iw dev 2>/dev/null | grep -A3 "Interface\|type" || true
else
  err "hostapd NOT running"
fi

hdr "DHCP / DNS (dnsmasq)"
if pgrep -x dnsmasq > /dev/null; then
  ok "dnsmasq running (PID: $(pgrep -x dnsmasq))"
  echo "  DHCP leases:"
  cat /var/lib/misc/dnsmasq.leases 2>/dev/null | sed 's/^/    /' || echo "    (none)"
else
  err "dnsmasq NOT running"
fi

hdr "Captive Portal (server.py)"
if pgrep -f server.py > /dev/null; then
  ok "server.py running (PID: $(pgrep -f server.py))"
else
  err "server.py NOT running"
fi

hdr "Firewall (iptables NAT rules)"
RULES=$(sudo iptables -t nat -L PREROUTING -n 2>/dev/null | grep -E "DNAT|REDIRECT" || true)
if [ -n "$RULES" ]; then
  ok "Walled garden iptables rules active:"
  echo "$RULES" | sed 's/^/    /'
else
  warn "No DNAT/REDIRECT rules found — walled garden may not be active"
fi

hdr "Kolibri (port 8080)"
if systemctl is-active --quiet kolibri 2>/dev/null; then
  ok "kolibri.service active"
elif pgrep -f kolibri > /dev/null; then
  ok "Kolibri process running"
else
  err "Kolibri NOT running"
  echo "  Try: sudo systemctl restart kolibri"
fi

hdr "NextCloud Docker Containers"
if command -v docker > /dev/null; then
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || err "docker not accessible"
else
  err "docker not installed"
fi

hdr "Systemd Services"
for svc in him-ap him-firewall him-webserver walled-garden kolibri docker; do
  state=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
  enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "unknown")
  if [ "$state" = "active" ]; then
    ok "$svc — $state (enabled: $enabled)"
  else
    warn "$svc — $state (enabled: $enabled)"
  fi
done

echo ""
echo "$SEP"
echo "  For detailed troubleshooting see: /opt/him-edu/troubleshooting/"
echo "$SEP"
echo ""
