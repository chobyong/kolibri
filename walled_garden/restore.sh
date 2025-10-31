#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="/home/him/walled_garden"
DRY_RUN=0

usage(){
  cat <<EOF
Usage: restore.sh [--src DIR] [--dry-run]

Options:
  --src DIR     Path to the extracted walled_garden directory (default: /home/him/walled_garden)
  --dry-run     Show what would be done but don't change the system

This script must be run as root. It will:
 - copy systemd unit files from SRC to /etc/systemd/system/
 - reload systemd, enable and start the him-* services in the proper order
 - optionally copy iptables rules from SRC to /etc/iptables/rules.v4 if present (will not install iptables-persistent)
 - print status and listening ports when finished
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src)
      SRC_DIR="$2"; shift 2;;
    --dry-run)
      DRY_RUN=1; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root. Use sudo." >&2
  exit 3
fi

echo "Restore script starting. src=$SRC_DIR dry-run=$DRY_RUN"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY RUN: no changes will be made"
fi

# Basic checks
if [[ ! -d "$SRC_DIR" ]]; then
  echo "Source directory $SRC_DIR not found." >&2
  exit 4
fi

# Install unit files
UNIT_FILES=("$SRC_DIR"/him-*.service)
if [[ $DRY_RUN -eq 1 ]]; then
  echo "Would copy unit files: ${UNIT_FILES[*]} -> /etc/systemd/system/"
else
  echo "Copying unit files to /etc/systemd/system/"
  cp -v ${UNIT_FILES[*]} /etc/systemd/system/ || true
fi

# Copy iptables rules if present
if [[ -f "$SRC_DIR/rules.v4" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "Would copy $SRC_DIR/rules.v4 -> /etc/iptables/rules.v4"
  else
    echo "Copying iptables rules to /etc/iptables/rules.v4"
    cp -v "$SRC_DIR/rules.v4" /etc/iptables/rules.v4
    echo "You should have iptables-persistent or a loader on the target to load /etc/iptables/rules.v4 at boot. This script does not install packages." 
  fi
else
  echo "No rules.v4 found in $SRC_DIR; skipping iptables rules copy."
fi

# Reload systemd and enable/start units
if [[ $DRY_RUN -eq 1 ]]; then
  echo "Would run: systemctl daemon-reload"
  echo "Would enable: him-firewall him-ap him-dnsmasq him-webserver"
  echo "Would start in order: him-firewall, him-ap, him-dnsmasq, him-webserver"
else
  echo "Reloading systemd daemon"
  systemctl daemon-reload
  echo "Enabling units"
  systemctl enable him-firewall him-ap him-dnsmasq him-webserver || true
  echo "Starting units in order"
  systemctl start him-firewall || true
  # small delay to allow firewall rules to apply
  sleep 1
  systemctl start him-ap || true
  sleep 1
  systemctl start him-dnsmasq || true
  sleep 1
  systemctl start him-webserver || true
fi

# Final status
if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY RUN complete"
  exit 0
fi

echo "Services status (short):"
systemctl --no-pager status him-firewall him-ap him-dnsmasq him-webserver || true

echo "Listening TCP ports for key services:"
ss -ltnp | egrep ':80|:443|:8080|:53' || true

echo "Restore finished. If iptables rules were copied you should verify /etc/iptables/rules.v4 is loaded at boot (install iptables-persistent or ensure a loader)."
