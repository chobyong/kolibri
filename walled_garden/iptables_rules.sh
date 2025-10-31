#!/usr/bin/env bash
set -euo pipefail

# Script to apply/clear iptables rules used by the walled garden.
# Run as root.

ACTION=${1:-apply}
IFACE="wlp3s0"
PORTAL_IP="10.42.0.1"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root" >&2
  exit 2
fi

if [ "$ACTION" = "clear" ]; then
  echo "Clearing NAT/forwarding rules"
  iptables -t nat -F || true
  iptables -F || true
  iptables -P OUTPUT ACCEPT || true # Reset OUTPUT policy to default
  exit 0
fi

echo "Applying NAT/redirect rules"
iptables -t nat -F
iptables -F FORWARD
iptables -F INPUT
iptables -F OUTPUT

# Set a default-deny policy on the OUTPUT chain to prevent the server from accessing the internet
iptables -P OUTPUT DROP

# Block all forwarding traffic by default to create the "walled garden"
iptables -A FORWARD -j DROP

# Allow all traffic on the loopback interface (IMPORTANT for local services like dnsmasq)
iptables -A INPUT -i lo -j ACCEPT

# Allow returning traffic for established connections on INPUT and OUTPUT chains
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Allow DHCP requests (for dnsmasq to assign IPs)
iptables -A INPUT -i "$IFACE" -p udp --dport 67 -j ACCEPT

# Allow DHCP replies to be sent out
iptables -A OUTPUT -o "$IFACE" -p udp --sport 67 --dport 68 -j ACCEPT

# Allow DNS queries (for captive portal redirection)
iptables -A INPUT -i "$IFACE" -p udp --dport 53 -j ACCEPT

# Allow access to the education content server on port 8080
iptables -A INPUT -i "$IFACE" -p tcp --dport 8080 -d "$PORTAL_IP" -j ACCEPT

# Allow access to the captive portal landing page on port 80
iptables -A INPUT -i "$IFACE" -p tcp --dport 80 -d "$PORTAL_IP" -j ACCEPT

# Redirect all other HTTP traffic to the portal page (keep HTTPS alone to avoid TLS breakage)
iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport 80 -j DNAT --to-destination "${PORTAL_IP}:80"
# Note: we intentionally do NOT redirect/redirect TLS (443) to avoid breaking TLS handshakes and cert errors.
# Modern captive-portal detection uses plain HTTP endpoints; DNS and HTTP redirect are sufficient in most cases.

echo "Done"
