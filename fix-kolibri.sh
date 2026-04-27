#!/usr/bin/env bash
# fix-kolibri.sh — Restores Kolibri content after main database reset
# Run as: sudo bash fix-kolibri.sh

set -euo pipefail

KOLIBRI_HOME=/home/him/.kolibri
DB_DIR="$KOLIBRI_HOME/content/databases"
CACHE_DIR="$KOLIBRI_HOME/process_cache"

log()  { echo -e "\n\033[1;34m>>>\033[0m $*"; }
ok()   { echo -e "  \033[1;32m✓\033[0m $*"; }
err()  { echo -e "  \033[1;31m✗\033[0m $*" >&2; }

export KOLIBRI_HOME

# ── Sanity checks ─────────────────────────────────────────────────────────────

if [ "$(id -u)" -ne 0 ]; then
  err "Run with sudo: sudo bash $0"
  exit 1
fi

if [ ! -d "$DB_DIR" ] || [ -z "$(ls "$DB_DIR"/*.sqlite3 2>/dev/null)" ]; then
  err "No channel databases found in $DB_DIR — nothing to restore."
  exit 1
fi

CHANNEL_IDS=$(ls "$DB_DIR"/*.sqlite3 | xargs -I{} basename {} .sqlite3)
CHANNEL_COUNT=$(echo "$CHANNEL_IDS" | wc -l)

echo ""
echo "============================================================"
echo "     Kolibri Content Restore — HIM Education"
echo "============================================================"
echo "  Channels found : $CHANNEL_COUNT"
echo "  KOLIBRI_HOME   : $KOLIBRI_HOME"
echo "============================================================"

# ── Step 1: Stop Kolibri ──────────────────────────────────────────────────────

log "Step 1/4 — Stopping Kolibri"

if systemctl is-active --quiet kolibri 2>/dev/null; then
  systemctl stop kolibri
  ok "Stopped via systemctl"
elif [ -f "$KOLIBRI_HOME/server.pid" ]; then
  PID=$(head -1 "$KOLIBRI_HOME/server.pid")
  if kill "$PID" 2>/dev/null; then
    sleep 3
    ok "Stopped PID $PID"
  else
    ok "Process $PID already stopped"
  fi
else
  ok "Kolibri was not running"
fi

# ── Step 2: Clear corrupted cache ─────────────────────────────────────────────

log "Step 2/4 — Clearing corrupted disk cache"
rm -rf "$CACHE_DIR"
mkdir -p "$CACHE_DIR"
chown him:him "$CACHE_DIR"
ok "Cache cleared"

# ── Step 3: Re-register channel metadata ──────────────────────────────────────

log "Step 3/4 — Re-registering $CHANNEL_COUNT channels (importchannel disk)"
FAILED_CH=()
for id in $CHANNEL_IDS; do
  echo -n "  $id ... "
  if sudo -u him KOLIBRI_HOME=$KOLIBRI_HOME kolibri manage importchannel disk "$id" "$KOLIBRI_HOME" 2>&1 \
      | grep -q "successfully imported"; then
    echo "OK"
  else
    echo "FAILED"
    FAILED_CH+=("$id")
  fi
done

if [ ${#FAILED_CH[@]} -gt 0 ]; then
  err "Failed channels (importchannel): ${FAILED_CH[*]}"
fi

# ── Step 4: Mark content available ────────────────────────────────────────────

log "Step 4/4 — Marking content available (importcontent disk)"
for id in $CHANNEL_IDS; do
  echo -n "  $id ... "
  sudo -u him KOLIBRI_HOME=$KOLIBRI_HOME kolibri manage importcontent disk "$id" "$KOLIBRI_HOME" 2>&1 \
    | grep "Setting availability" || echo "done"
done

# ── Restart Kolibri ───────────────────────────────────────────────────────────

log "Restarting Kolibri"
if systemctl cat kolibri &>/dev/null; then
  systemctl start kolibri
  ok "Started via systemctl"
else
  sudo -u him KOLIBRI_HOME=$KOLIBRI_HOME kolibri start --background
  ok "Started as him user"
fi

sleep 4

echo ""
echo "============================================================"
echo "     Restore Complete!"
echo "============================================================"
echo "  Kolibri should be available at: http://10.42.0.1:8080/"
echo ""
echo "  Verify with:"
echo "    tail -20 $KOLIBRI_HOME/logs/kolibri.txt"
echo "============================================================"
