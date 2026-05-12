#!/bin/bash
# Rebuild NextCloud trusted_domains with all current RFC 1918 IPs.
# Run on boot (after network-online.target) so NextCloud accepts connections
# from whichever interface the host happens to be on.

set -euo pipefail

COMPOSE_DIR="/opt/him-edu/nextcloud"
OCC="docker exec --user www-data nextcloud php occ"

# Wait up to 30s for the NextCloud container to be ready
for i in $(seq 1 30); do
    docker exec nextcloud true 2>/dev/null && break
    sleep 1
done

# Fixed entries that are always trusted
declare -a DOMAINS=(
    "localhost"
    "10.42.0.1"
    "10.42.0.1:8081"
)

# Add every current RFC 1918 address (skip loopback and Docker bridges)
while IFS= read -r ip; do
    if [[ "$ip" =~ ^10\. ]] || \
       [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] || \
       [[ "$ip" =~ ^192\.168\. ]]; then
        DOMAINS+=("$ip" "${ip}:8081")
    fi
done < <(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Write the full list to NextCloud
i=0
for domain in "${DOMAINS[@]}"; do
    $OCC config:system:set trusted_domains "$i" --value="$domain"
    ((i++))
done

echo "NextCloud trusted_domains updated (${#DOMAINS[@]} entries):"
$OCC config:system:get trusted_domains
