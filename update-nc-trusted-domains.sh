#!/bin/bash
# Rebuild NextCloud trusted_domains with all current RFC 1918 IPs.
# Run on boot (after network-online.target) so NextCloud accepts connections
# from whichever interface the host happens to be on.

set -euo pipefail

COMPOSE_DIR="/opt/him-edu/nextcloud"
OCC="docker exec --user www-data nextcloud php occ"

# Wait up to 60s for the NextCloud container to be ready
for i in $(seq 1 60); do
    docker exec nextcloud true 2>/dev/null && break
    sleep 1
done

# Build deduplicated trusted domain list using an associative array as a set
declare -A SEEN
declare -a DOMAINS

_add() { [[ -z "${SEEN[$1]+x}" ]] && DOMAINS+=("$1") && SEEN[$1]=1; }

# Fixed entries always trusted (Cloudflare tunnel hostname included)
_add "localhost"
_add "nextcloud.heaveninme.us"

# Add every current RFC 1918 address (covers AP, ethernet, any future interface)
while IFS= read -r ip; do
    if [[ "$ip" =~ ^10\. ]] || \
       [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] || \
       [[ "$ip" =~ ^192\.168\. ]]; then
        _add "$ip"
        _add "${ip}:8081"
    fi
done < <(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Write the full list to NextCloud
i=0
for domain in "${DOMAINS[@]}"; do
    $OCC config:system:set trusted_domains "$i" --value="$domain"
    i=$(( i + 1 ))
done

echo "NextCloud trusted_domains updated (${#DOMAINS[@]} entries):"
$OCC config:system:get trusted_domains
