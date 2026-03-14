#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
#  HIM Education Server — Full Installation Script
# =============================================================================
#  This script sets up a complete HIM Education offline server from scratch:
#    - System prerequisites (git, curl, docker, docker-compose)
#    - Docker configured for non-root user
#    - Kolibri learning platform
#    - NextCloud with Calendar, Notes, and NextCloud Office (Collabora)
#    - Walled garden hotspot (hostapd, dnsmasq, iptables, captive portal)
#
#  Usage:   sudo ./install.sh
#  Tested:  Debian 12 / Ubuntu 22.04+
# =============================================================================

AP_IP="10.42.0.1"
SSID="him-edu"
PASSPHRASE="1234567890"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NEXTCLOUD_DIR="${SCRIPT_DIR}/nextcloud"
LOG_FILE="${SCRIPT_DIR}/install.log"
TARGET_USER="${SUDO_USER:-him}"\nMACHINE_HOSTNAME="$(hostname)"

# NextCloud app versions (update these when upgrading)
CALENDAR_VER="6.2.1"
NOTES_VER="4.13.0"
RICHDOCS_VER="10.1.0"

# --- Helpers -----------------------------------------------------------------

log()  { echo -e "\n\033[1;34m>>>\033[0m $*"; }
ok()   { echo -e "  \033[1;32m✓\033[0m $*"; }
warn() { echo -e "  \033[1;33m!\033[0m $*"; }
err()  { echo -e "  \033[1;31m✗\033[0m $*" >&2; }

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run with sudo:  sudo ./install.sh"
    exit 1
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

wait_for_container() {
  local name="$1" max="${2:-60}" i=0
  while [ $i -lt "$max" ]; do
    if docker inspect --format='{{.State.Running}}' "$name" 2>/dev/null | grep -q true; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  err "Container $name did not start within ${max}s"
  return 1
}

# =============================================================================
#  PHASE 0 — Hostname
# =============================================================================

setup_hostname() {
  log "Phase 0: Set Hostname"

  local current_hostname
  current_hostname=$(hostname)
  echo "  Current hostname: $current_hostname"

  local new_hostname
  read -rp "  Enter new hostname (press Enter to keep '$current_hostname'): " new_hostname

  if [ -z "$new_hostname" ]; then
    ok "Keeping hostname: $current_hostname"
    MACHINE_HOSTNAME="$current_hostname"
  else
    hostnamectl set-hostname "$new_hostname"
    sed -i "s/127\.0\.1\.1.*/127.0.1.1\t$new_hostname/" /etc/hosts
    if ! grep -q "127.0.1.1" /etc/hosts; then
      echo -e "127.0.1.1\t$new_hostname" >> /etc/hosts
    fi
    ok "Hostname set to: $new_hostname"
    MACHINE_HOSTNAME="$new_hostname"
  fi
}

# =============================================================================
#  PHASE 1 — System Prerequisites
# =============================================================================

install_prerequisites() {
  log "Phase 1: System Prerequisites"

  apt-get update -qq

  # git
  if command_exists git; then
    ok "git already installed ($(git --version | cut -d' ' -f3))"
  else
    apt-get install -y git
    ok "git installed"
  fi

  # curl
  if command_exists curl; then
    ok "curl already installed"
  else
    apt-get install -y curl
    ok "curl installed"
  fi

  # hostapd & dnsmasq
  for pkg in hostapd dnsmasq; do
    if command_exists "$pkg"; then
      ok "$pkg already installed"
    else
      apt-get install -y "$pkg"
      ok "$pkg installed"
    fi
  done
  # Disable system-level services — we manage them ourselves
  systemctl disable --now hostapd 2>/dev/null || true
  systemctl disable --now dnsmasq 2>/dev/null || true

  # iptables, python3, openssl, iw
  for pkg in iptables python3 openssl iw; do
    if command_exists "$pkg"; then
      ok "$pkg already installed"
    else
      apt-get install -y "$pkg"
      ok "$pkg installed"
    fi
  done

  # Disable suspend/hibernate
  systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
  ok "Power saving disabled (suspend/hibernate masked)"
}

# =============================================================================
#  PHASE 2 — Docker
# =============================================================================

install_docker() {
  log "Phase 2: Docker"

  if command_exists docker; then
    ok "Docker already installed ($(docker --version | cut -d' ' -f3 | tr -d ','))"
  else
    apt-get install -y docker.io
    systemctl enable --now docker
    ok "Docker installed and started"
  fi

  # docker compose (v2 plugin)
  if docker compose version >/dev/null 2>&1; then
    ok "Docker Compose plugin available"
  else
    apt-get install -y docker-compose-plugin 2>/dev/null || apt-get install -y docker-compose
    ok "Docker Compose installed"
  fi

  # Allow TARGET_USER to run docker without sudo
  if id -nG "$TARGET_USER" | grep -qw docker; then
    ok "User '$TARGET_USER' already in docker group"
  else
    usermod -aG docker "$TARGET_USER"
    ok "User '$TARGET_USER' added to docker group (re-login for effect)"
  fi
}

# =============================================================================
#  PHASE 3 — Kolibri
# =============================================================================

install_kolibri() {
  log "Phase 3: Kolibri Learning Platform"

  if command_exists kolibri; then
    ok "Kolibri already installed ($(kolibri --version 2>/dev/null || echo 'unknown'))"
    # Make sure it's running
    if systemctl is-active --quiet kolibri 2>/dev/null; then
      ok "Kolibri service is running"
    else
      systemctl enable --now kolibri 2>/dev/null || true
      ok "Kolibri service enabled and started"
    fi
    return
  fi

  # Look for .deb in project directory
  local deb
  deb=$(find "$SCRIPT_DIR" -maxdepth 1 -name "kolibri*.deb" 2>/dev/null | head -n 1)

  if [ -n "$deb" ]; then
    echo "  Installing from: $deb"
    dpkg -i "$deb" || true
    apt-get install -f -y
    ok "Kolibri installed from local .deb"
  else
    # Try to download latest
    echo "  No local .deb found. Attempting to download..."
    local kolibri_url="https://learningequality.org/r/kolibri-deb-latest"
    local tmp_deb="/tmp/kolibri-latest.deb"
    if curl -fsSL -o "$tmp_deb" "$kolibri_url" 2>/dev/null; then
      dpkg -i "$tmp_deb" || true
      apt-get install -f -y
      rm -f "$tmp_deb"
      ok "Kolibri downloaded and installed"
    else
      warn "Could not download Kolibri. No internet or URL changed."
      warn "Place a kolibri*.deb in $SCRIPT_DIR and re-run, or install manually."
      return
    fi
  fi

  systemctl enable --now kolibri 2>/dev/null || true
  ok "Kolibri service enabled"
}

# =============================================================================
#  PHASE 4 — NextCloud (Docker)
# =============================================================================

install_nextcloud() {
  log "Phase 4: NextCloud Docker Stack"

  # Create volume directories
  echo "  Creating volume directories..."
  mkdir -p "$NEXTCLOUD_DIR"/{html,custom_apps,config,data,nextclouddb,redis,npm-data,letsencrypt}
  ok "Volume directories ready"

  # Start containers
  echo "  Starting Docker Compose stack..."
  cd "$NEXTCLOUD_DIR"
  docker compose down 2>/dev/null || true
  docker compose up -d
  ok "Containers started"

  # Wait for NextCloud container
  echo "  Waiting for NextCloud to be ready..."
  wait_for_container nextcloud 90

  # Check if already installed
  sleep 10
  local installed
  installed=$(docker exec -u www-data nextcloud php occ status --output=json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('installed',False))" 2>/dev/null || echo "False")

  if [ "$installed" = "True" ]; then
    ok "NextCloud already installed"
  else
    echo "  Running initial NextCloud setup..."
    docker exec -u www-data nextcloud php occ maintenance:install \
      --database "mysql" \
      --database-host "nextclouddb" \
      --database-name "nextcloud" \
      --database-user "nextcloud" \
      --database-pass "dbpassword" \
      --admin-user "admin" \
      --admin-pass "admin123"
    ok "NextCloud installed (admin/admin123)"
  fi

  # Configure trusted domains and settings
  echo "  Configuring NextCloud settings..."
  docker exec -u www-data nextcloud php occ config:system:set trusted_domains 1 --value="${AP_IP}:8081"
  docker exec -u www-data nextcloud php occ config:system:set trusted_domains 2 --value="${AP_IP}"
  docker exec -u www-data nextcloud php occ config:system:set overwrite.cli.url --value="http://${AP_IP}:8081"
  docker exec -u www-data nextcloud php occ config:system:set overwriteprotocol --value="http"
  docker exec -u www-data nextcloud php occ config:system:set allow_local_remote_servers --type boolean --value true
  docker exec -u www-data nextcloud php occ config:system:set has_internet_connection --type boolean --value true
  docker exec -u www-data nextcloud php occ config:system:set appstoreenabled --type boolean --value true
  ok "NextCloud configured"
}

# =============================================================================
#  PHASE 5 — NextCloud Apps
# =============================================================================

install_nc_app() {
  local app_id="$1" app_ver="$2" app_url="$3"

  # Check if already enabled
  if docker exec -u www-data nextcloud php occ app:list --enabled 2>/dev/null | grep -q "  - ${app_id}:"; then
    ok "$app_id already installed and enabled"
    return
  fi

  # Download and extract
  echo "  Installing $app_id v$app_ver..."
  docker exec nextcloud bash -c "
    cd /tmp &&
    curl -fsSL -o ${app_id}.tar.gz ${app_url} &&
    tar xzf ${app_id}.tar.gz -C /var/www/html/custom_apps/ &&
    chown -R www-data:www-data /var/www/html/custom_apps/${app_id} &&
    rm -f ${app_id}.tar.gz
  "
  docker exec -u www-data nextcloud php occ app:enable "$app_id"
  ok "$app_id v$app_ver installed and enabled"
}

install_nextcloud_apps() {
  log "Phase 5: NextCloud Apps (Calendar, Notes, Office)"

  install_nc_app "calendar" "$CALENDAR_VER" \
    "https://github.com/nextcloud-releases/calendar/releases/download/v${CALENDAR_VER}/calendar-v${CALENDAR_VER}.tar.gz"

  install_nc_app "notes" "$NOTES_VER" \
    "https://github.com/nextcloud-releases/notes/releases/download/v${NOTES_VER}/notes-v${NOTES_VER}.tar.gz"

  install_nc_app "richdocuments" "$RICHDOCS_VER" \
    "https://github.com/nextcloud-releases/richdocuments/releases/download/v${RICHDOCS_VER}/richdocuments-v${RICHDOCS_VER}.tar.gz"

  # Configure Collabora (NextCloud Office)
  echo "  Configuring Collabora integration..."
  docker exec -u www-data nextcloud php occ config:app:set richdocuments wopi_url --value="http://collabora:9980"
  docker exec -u www-data nextcloud php occ config:app:set richdocuments public_wopi_url --value="http://${AP_IP}:9980"
  docker exec -u www-data nextcloud php occ config:app:set richdocuments wopi_allowlist --value="10.42.0.0/24,172.18.0.0/16"
  ok "Collabora WOPI configured"
}

# =============================================================================
#  PHASE 6 — Walled Garden Setup
# =============================================================================

setup_walled_garden() {
  log "Phase 6: Walled Garden (Hotspot, DHCP, DNS, Captive Portal)"

  # Make scripts executable
  chmod +x "$SCRIPT_DIR/start_ap.sh" \
           "$SCRIPT_DIR/stop_ap.sh" \
           "$SCRIPT_DIR/iptables_rules.sh" \
           "$SCRIPT_DIR/server.py"
  ok "Scripts set executable"

  # Verify wireless interface
  local iface
  iface=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -1)
  if [ -z "$iface" ]; then
    iface=$(ls /sys/class/net/ | grep -E '^wl' | head -1)
  fi
  if [ -n "$iface" ]; then
    ok "Wireless interface detected: $iface"
  else
    warn "No wireless interface found — hotspot won't work without one"
  fi

  # Install systemd services
  echo "  Installing systemd services..."
  for svc in him-ap.service him-firewall.service him-webserver.service walled-garden.service; do
    if [ -f "$SCRIPT_DIR/$svc" ]; then
      cp "$SCRIPT_DIR/$svc" /etc/systemd/system/
    fi
  done
  systemctl daemon-reload
  ok "Systemd services installed"

  # Ensure NetworkManager is running
  if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    ok "NetworkManager is active"
  else
    systemctl enable --now NetworkManager 2>/dev/null || warn "NetworkManager not found"
  fi
}

# =============================================================================
#  PHASE 7 — Final Verification
# =============================================================================

verify_installation() {
  log "Phase 7: Verification"

  echo ""
  echo "  Checking components..."

  # git
  command_exists git && ok "git" || err "git NOT found"

  # curl
  command_exists curl && ok "curl" || err "curl NOT found"

  # docker
  command_exists docker && ok "docker" || err "docker NOT found"

  # docker compose
  docker compose version >/dev/null 2>&1 && ok "docker compose" || err "docker compose NOT found"

  # docker group
  id -nG "$TARGET_USER" | grep -qw docker && ok "User '$TARGET_USER' in docker group" || warn "User '$TARGET_USER' NOT in docker group yet (re-login needed)"

  # hostapd
  command_exists hostapd && ok "hostapd" || err "hostapd NOT found"

  # dnsmasq
  command_exists dnsmasq && ok "dnsmasq" || err "dnsmasq NOT found"

  # Kolibri
  if command_exists kolibri; then
    ok "Kolibri installed"
  else
    warn "Kolibri not installed (place .deb in project dir and re-run)"
  fi

  # NextCloud containers
  for ctr in nextcloud nextcloud-db collabora redis nginx-proxy; do
    if docker inspect --format='{{.State.Running}}' "$ctr" 2>/dev/null | grep -q true; then
      ok "Container: $ctr"
    else
      err "Container: $ctr NOT running"
    fi
  done

  # NextCloud apps
  local apps
  apps=$(docker exec -u www-data nextcloud php occ app:list --enabled 2>/dev/null || echo "")
  for app_id in calendar notes richdocuments; do
    if echo "$apps" | grep -q "  - ${app_id}:"; then
      ok "NextCloud app: $app_id"
    else
      err "NextCloud app: $app_id NOT enabled"
    fi
  done

  # Wireless
  local iface
  iface=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -1)
  if [ -n "$iface" ]; then
    ok "Wireless interface: $iface"
  else
    warn "No wireless interface detected"
  fi

  # Tailscale
  if command_exists tailscale && tailscale status >/dev/null 2>&1; then
    ok "Tailscale connected ($(tailscale ip -4 2>/dev/null || echo 'unknown IP'))"
  else
    warn "Tailscale not connected"
  fi

  # Hostname
  ok "Hostname: $(hostname)"
}

# =============================================================================
#  PHASE 7.5 — Tailscale
# =============================================================================

install_tailscale() {
  log "Phase 8: Tailscale"

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
  local ts_status
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
}

# =============================================================================
#  MAIN
# =============================================================================

main() {
  check_root

  echo ""
  echo "============================================================"
  echo "     HIM Education Server — Full Installation"
  echo "============================================================"
  echo "  User:   $TARGET_USER"
  echo "  SSID:   $SSID"
  echo "  AP IP:  $AP_IP"
  echo "  Dir:    $SCRIPT_DIR"
  echo "============================================================"

  setup_hostname
  install_prerequisites
  install_docker
  install_kolibri
  install_nextcloud
  install_nextcloud_apps
  setup_walled_garden
  install_tailscale
  verify_installation

  echo ""
  echo "============================================================"
  echo "     Installation Complete!"
  echo "============================================================"
  echo ""
  echo "  To start the walled garden:"
  echo "    sudo ./start_ap.sh"
  echo ""
  echo "  To enable on boot:"
  echo "    sudo systemctl enable walled-garden"
  echo ""
  echo "  Services:"
  echo "    Landing Page:  http://${AP_IP}/"
  echo "    Kolibri:       http://${AP_IP}:8080/"
  echo "    NextCloud:     http://${AP_IP}:8081/  (admin / admin123)"
  echo "    Collabora:     http://${AP_IP}:9980/"
  echo "    Nginx Proxy:   http://${AP_IP}:81/"
  echo ""
  echo "  Wi-Fi:  SSID=$SSID  Password=$PASSPHRASE"
  echo ""
  echo "  Tailscale SSH: enabled (hostname: ${MACHINE_HOSTNAME})"
  echo ""
  echo "  NOTE: Log out and back in for docker group to take effect."
  echo "============================================================"
}

main "$@" 2>&1 | tee "$LOG_FILE"
