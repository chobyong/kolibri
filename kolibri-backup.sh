#!/bin/bash
# Backup or restore Kolibri facility data (users, classes, assignments, progress).
# Does NOT include content (278 GB) — install content separately on the target host.
#
# Usage:
#   ./kolibri-backup.sh backup [output-file.tar.gz]
#   ./kolibri-backup.sh restore <backup-file.tar.gz>
#   ./kolibri-backup.sh sync <target-kolibri-url>   (live sync, both hosts must be online)

set -e

KOLIBRI_HOME="/home/him/.kolibri"
KOLIBRI_USER="him"
DEFAULT_BACKUP_DIR="/opt/him-edu/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Files that hold all facility data (users, classes, assignments, progress).
# The WAL file must be included — it may contain unflushed transactions.
DB_FILES=(
    "db.sqlite3"
    "db.sqlite3-shm"
    "db.sqlite3-wal"
    "options.ini"
    "plugins.json"
)

usage() {
    echo "Usage:"
    echo "  $0 backup [output-file.tar.gz]"
    echo "  $0 restore <backup-file.tar.gz>"
    echo "  $0 sync <target-kolibri-url>  (e.g. http://192.168.1.50:8080)"
    exit 1
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: Run as root (sudo $0 $*)"
        exit 1
    fi
}

stop_kolibri() {
    echo "Stopping Kolibri..."
    systemctl stop kolibri || true
    # Wait for WAL checkpoint to flush
    sleep 2
}

start_kolibri() {
    echo "Starting Kolibri..."
    systemctl start kolibri
}

cmd_backup() {
    require_root
    mkdir -p "$DEFAULT_BACKUP_DIR"
    local outfile="${1:-$DEFAULT_BACKUP_DIR/kolibri-backup-$TIMESTAMP.tar.gz}"

    stop_kolibri

    echo "Creating backup: $outfile"
    # Collect only the files that exist
    local files_to_backup=()
    for f in "${DB_FILES[@]}"; do
        [[ -f "$KOLIBRI_HOME/$f" ]] && files_to_backup+=("$f")
    done

    tar -czf "$outfile" -C "$KOLIBRI_HOME" "${files_to_backup[@]}"

    start_kolibri

    local size
    size=$(du -sh "$outfile" | cut -f1)
    echo ""
    echo "Backup complete: $outfile ($size)"
    echo ""
    echo "To restore on another host:"
    echo "  1. Install Kolibri $( kolibri --version 2>/dev/null | grep -o '[0-9.]*' | head -1 ) on the target"
    echo "  2. Copy $outfile to the target"
    echo "  3. Run:  sudo ./kolibri-backup.sh restore $(basename "$outfile")"
}

cmd_restore() {
    require_root
    local infile="$1"
    [[ -z "$infile" ]] && usage
    [[ ! -f "$infile" ]] && { echo "ERROR: File not found: $infile"; exit 1; }

    echo "Restoring from: $infile"
    echo "WARNING: This will OVERWRITE all current Kolibri users, classes, and progress."
    read -rp "Continue? [y/N] " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Aborted."; exit 0; }

    stop_kolibri

    # Back up existing DB before overwrite
    local safeguard="$DEFAULT_BACKUP_DIR/pre-restore-$TIMESTAMP.tar.gz"
    mkdir -p "$DEFAULT_BACKUP_DIR"
    echo "Saving current DB to $safeguard before overwriting..."
    local existing=()
    for f in "${DB_FILES[@]}"; do
        [[ -f "$KOLIBRI_HOME/$f" ]] && existing+=("$f")
    done
    [[ ${#existing[@]} -gt 0 ]] && tar -czf "$safeguard" -C "$KOLIBRI_HOME" "${existing[@]}"

    echo "Extracting backup..."
    tar -xzf "$infile" -C "$KOLIBRI_HOME"
    chown "$KOLIBRI_USER:$KOLIBRI_USER" "$KOLIBRI_HOME"/db.sqlite3* "$KOLIBRI_HOME"/options.ini "$KOLIBRI_HOME"/plugins.json 2>/dev/null || true

    start_kolibri

    echo ""
    echo "Restore complete. Kolibri is running."
    echo "Pre-restore DB saved at: $safeguard"
}

cmd_sync() {
    require_root
    local target_url="$1"
    [[ -z "$target_url" ]] && usage

    echo "Syncing facility to $target_url"
    echo "Enter the admin credentials for the TARGET Kolibri instance:"
    read -rp "  Username: " sync_user
    read -rsp "  Password: " sync_pass
    echo ""

    sudo -u "$KOLIBRI_USER" kolibri manage fullfacilitysync \
        --base-url "$target_url" \
        --username "$sync_user" \
        --password "$sync_pass"

    echo ""
    echo "Sync complete."
}

case "${1:-}" in
    backup)  cmd_backup "${2:-}" ;;
    restore) cmd_restore "${2:-}" ;;
    sync)    cmd_sync "${2:-}" ;;
    *)       usage ;;
esac
