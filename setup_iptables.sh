#!/bin/bash

# Flush existing rules
iptables -t nat -F
iptables -t filter -F

# Allow established connections
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Redirect all HTTP traffic
iptables -t nat -A PREROUTING -i wlp3s0 -p tcp --dport 80 -j DNAT --to-destination 10.42.0.1:80
iptables -t nat -A PREROUTING -i wlp3s0 -p tcp --dport 443 -j DNAT --to-destination 10.42.0.1:80

# Redirect DNS queries to our server
iptables -t nat -A PREROUTING -i wlp3s0 -p udp --dport 53 -j DNAT --to-destination 10.42.0.1:53
iptables -t nat -A PREROUTING -i wlp3s0 -p tcp --dport 53 -j DNAT --to-destination 10.42.0.1:53

# Masquerade all outgoing traffic (even though we're blocking it, this ensures proper routing)
iptables -t nat -A POSTROUTING -o wlp3s0 -j MASQUERADE

# Allow access to localhost:8080
iptables -t nat -A PREROUTING -i wlp3s0 -p tcp --dport 8080 -j DNAT --to-destination 10.42.0.1:8080

# Block all other outgoing traffic
iptables -A FORWARD -i wlp3s0 -j DROP

# Save rules
iptables-save > /etc/iptables/rules.v4