#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
#  HIM Education Server — Tailscale (optional remote access)
# =============================================================================
#  Sets up Tailscale with SSH enabled, for remote administration outside the
#  Cloudflare tunnel. Run this on its own, separate from install.sh, since it
#  needs internet and — on first login — a browser to complete auth.
#
#  Usage: sudo ./install-tailscale.sh
# =============================================================================

MACHINE_HOSTNAME="$(hostname)"

log()  { echo -e "\n\033[1;34m>>>\033[0m $*"; }
ok()   { echo -e "  \033[1;32m✓\033[0m $*"; }
err()  { echo -e "  \033[1;31m✗\033[0m $*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run with sudo:  sudo ./install-tailscale.sh"
  exit 1
fi

log "Tailscale Setup"

if command_exists tailscale; then
  ok "Tailscale already installed ($(tailscale version 2>/dev/null | head -1))"
else
  echo "  Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  ok "Tailscale installed"
fi

systemctl enable --now tailscaled 2>/dev/null || true
ok "tailscaled service enabled"

# Check if already authenticated
ts_status=$(tailscale status 2>&1 || true)
if echo "$ts_status" | grep -qiE "stopped|logged out|not logged in|NeedsLogin"; then
  echo ""
  echo "  Activating Tailscale with SSH enabled..."
  echo "  A login URL will appear — open it in a browser to authenticate."
  echo ""
  tailscale up --ssh --hostname="${MACHINE_HOSTNAME}" --accept-routes
  ok "Tailscale activated (hostname: ${MACHINE_HOSTNAME}, SSH enabled)"
else
  # Already connected, update settings
  tailscale set --ssh --hostname="${MACHINE_HOSTNAME}" 2>/dev/null || \
    tailscale up --ssh --hostname="${MACHINE_HOSTNAME}" --accept-routes 2>/dev/null || true
  ok "Tailscale already connected — updated hostname to ${MACHINE_HOSTNAME} with SSH"
fi

echo ""
echo "  Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'unknown')"
echo ""
