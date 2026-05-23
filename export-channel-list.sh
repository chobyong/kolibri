#!/usr/bin/env bash
# Exports the list of currently installed Kolibri channels to channels.json.
# Copy channels.json to a new host, then run:
#   sudo ./import-kolibri-channels.sh from-file channels.json

set -euo pipefail

KOLIBRI_URL="${1:-http://localhost:8080}"
OUTPUT="${2:-/opt/him-edu/channels.json}"

echo "Fetching installed channels from $KOLIBRI_URL ..."

python3 - <<PYEOF
import json, urllib.request, sys

url = "$KOLIBRI_URL/api/public/v1/channels/"
try:
    with urllib.request.urlopen(url, timeout=10) as r:
        channels = json.load(r)
except Exception as e:
    print(f"ERROR: Could not reach Kolibri at $KOLIBRI_URL: {e}", file=sys.stderr)
    sys.exit(1)

out = [{"id": c["id"], "name": c["name"]} for c in channels]
with open("$OUTPUT", "w") as f:
    json.dump(out, f, indent=2)

print(f"Saved {len(out)} channels to $OUTPUT")
for c in out:
    print(f"  {c['id']}  {c['name']}")
PYEOF
