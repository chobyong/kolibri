#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
#  HIM Education Server — Post-Install Provisioning Script
#  Reproduces the full HIM-010 configuration on a fresh Debian 13 (trixie) install
#
#  Run as root:  sudo bash provision.sh
#  Idempotent:  safe to re-run
# =============================================================================

AP_IP="10.42.0.1"
SSID="him-edu"
PASSPHRASE="1234567890"
HOSTNAME_TARGET="HIM-010"
TARGET_USER="him"
INSTALL_DIR="/opt/him-edu"
NEXTCLOUD_DIR="${INSTALL_DIR}/nextcloud"
LOG_FILE="/var/log/him-provision.log"
KOLIBRI_URL="https://learningequality.org/r/kolibri-deb-latest"
IFACE_CONF="/opt/him-edu/wifi-iface.conf"   # persists detected interface

# Redirect output to log while still showing on console
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== HIM Provision started: $(date) ==="

# --- Helpers -----------------------------------------------------------------
log()  { echo -e "\n\033[1;34m[HIM]\033[0m $*"; }
ok()   { echo -e "  \033[1;32m✓\033[0m $*"; }
warn() { echo -e "  \033[1;33m!\033[0m $*"; }
err()  { echo -e "  \033[1;31m✗\033[0m $*" >&2; }
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

if [ "$(id -u)" -ne 0 ]; then
  err "Must run as root: sudo bash provision.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
#  detect_wifi_iface — universal wireless interface detection
#
#  Priority order:
#    1. Previously saved value in $IFACE_CONF (consistent across re-runs)
#    2. iw dev  (works with any naming convention including wlx<mac> USB adapters)
#    3. /sys/class/net scan  (fallback: wlan*, wlp*, wlx*, wls*)
#
#  Also validates that the chosen interface supports AP mode.
# ---------------------------------------------------------------------------
detect_wifi_iface() {
  local iface=""

  # 1. Use saved value if present and interface still exists
  if [ -f "$IFACE_CONF" ]; then
    local saved
    saved=$(cat "$IFACE_CONF")
    if [ -n "$saved" ] && [ -d "/sys/class/net/$saved" ]; then
      echo "$saved"
      return 0
    fi
  fi

  # 2. iw dev — picks up all naming conventions (wlan0, wlp2s0, wlx<mac>, etc.)
  if cmd_exists iw; then
    iface=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -1)
  fi

  # 3. /sys/class/net scan — catches any interface whose phy80211 link exists
  if [ -z "$iface" ]; then
    for dev in /sys/class/net/*/phy80211; do
      [ -e "$dev" ] && iface=$(basename "$(dirname "$dev")") && break
    done
  fi

  # 4. Last resort: name-pattern match (wlan*, wlp*, wlx*, wls*, wlo*)
  if [ -z "$iface" ]; then
    iface=$(ls /sys/class/net/ 2>/dev/null | grep -E '^wl' | head -1)
  fi

  if [ -z "$iface" ]; then
    return 1
  fi

  # Validate AP mode support
  if cmd_exists iw; then
    if ! iw phy "$(cat /sys/class/net/${iface}/phy80211/name 2>/dev/null)" \
        info 2>/dev/null | grep -q "AP"; then
      warn "Interface $iface may not support AP mode — hotspot might fail."
      warn "Check: iw phy \$(cat /sys/class/net/${iface}/phy80211/name) info | grep -A10 'Supported interface modes'"
    fi
  fi

  # Persist for all subsequent scripts and service files
  mkdir -p "$(dirname "$IFACE_CONF")"
  echo "$iface" > "$IFACE_CONF"
  echo "$iface"
}

# =============================================================================
#  PHASE 0 — Hostname
# =============================================================================
log "Phase 0: Hostname"
if [ "$(hostname)" != "$HOSTNAME_TARGET" ]; then
  hostnamectl set-hostname "$HOSTNAME_TARGET"
  sed -i "s/127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME_TARGET}/" /etc/hosts
  grep -q "127.0.1.1" /etc/hosts || echo -e "127.0.1.1\t${HOSTNAME_TARGET}" >> /etc/hosts
  ok "Hostname set to $HOSTNAME_TARGET"
else
  ok "Hostname already $HOSTNAME_TARGET"
fi

# =============================================================================
#  PHASE 1 — System Prerequisites
# =============================================================================
log "Phase 1: System Prerequisites"

apt-get update -qq

PREREQS="git curl wget vim htop iw wireless-tools rfkill hostapd dnsmasq
         iptables iptables-persistent python3 openssl network-manager
         ca-certificates gnupg lsb-release apt-transport-https
         net-tools iputils-ping dnsutils lsof tmux unzip jq"

for pkg in $PREREQS; do
  if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
    ok "$pkg already installed"
  else
    apt-get install -y "$pkg"
    ok "$pkg installed"
  fi
done

# Disable system-managed hostapd & dnsmasq — we manage them ourselves
systemctl disable --now hostapd 2>/dev/null || true
systemctl disable --now dnsmasq 2>/dev/null || true

# Enable IP forwarding — required for iptables NAT/DNAT (walled garden)
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-him-forward.conf
sysctl -w net.ipv4.ip_forward=1
ok "IP forwarding enabled (persistent)"

# Disable suspend/hibernate on a server
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
ok "Sleep/suspend masked"

# =============================================================================
#  PHASE 2 — Docker (official repo)
# =============================================================================
log "Phase 2: Docker"

if cmd_exists docker; then
  ok "Docker already installed: $(docker --version)"
else
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  ok "Docker installed and started"
fi

if docker compose version >/dev/null 2>&1; then
  ok "Docker Compose plugin available"
else
  apt-get install -y docker-compose-plugin 2>/dev/null || \
    apt-get install -y docker-compose
  ok "Docker Compose installed"
fi

if id -nG "$TARGET_USER" 2>/dev/null | grep -qw docker; then
  ok "User $TARGET_USER already in docker group"
else
  usermod -aG docker "$TARGET_USER" 2>/dev/null || true
  ok "User $TARGET_USER added to docker group"
fi

# =============================================================================
#  PHASE 3 — Tailscale
# =============================================================================
log "Phase 3: Tailscale"

if cmd_exists tailscale; then
  ok "Tailscale already installed"
else
  curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.gpg \
    | gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] \
https://pkgs.tailscale.com/stable/debian trixie main" \
    > /etc/apt/sources.list.d/tailscale.list
  apt-get update -qq
  apt-get install -y tailscale
  systemctl enable --now tailscaled
  ok "Tailscale installed — run 'tailscale up' to authenticate"
fi

# =============================================================================
#  PHASE 4 — Kolibri Learning Platform
# =============================================================================
log "Phase 4: Kolibri"

if cmd_exists kolibri; then
  ok "Kolibri already installed: $(kolibri --version 2>/dev/null || echo 'unknown')"
else
  # Check for local .deb first
  LOCAL_DEB=$(find "$INSTALL_DIR" /home/"$TARGET_USER" -maxdepth 3 \
    -name "kolibri*.deb" 2>/dev/null | head -1)

  if [ -n "$LOCAL_DEB" ]; then
    log "Installing Kolibri from local .deb: $LOCAL_DEB"
    dpkg -i "$LOCAL_DEB" || true
    apt-get install -f -y
    ok "Kolibri installed from local .deb"
  else
    log "Downloading Kolibri .deb..."
    TMP_DEB="/tmp/kolibri-latest.deb"
    if curl -fsSL -o "$TMP_DEB" "$KOLIBRI_URL"; then
      dpkg -i "$TMP_DEB" || true
      apt-get install -f -y
      rm -f "$TMP_DEB"
      ok "Kolibri downloaded and installed"
    else
      warn "Cannot download Kolibri — no internet or URL changed."
      warn "Place a kolibri*.deb in $INSTALL_DIR and re-run provision.sh"
    fi
  fi
fi

if cmd_exists kolibri; then
  systemctl enable --now kolibri 2>/dev/null || true
  ok "Kolibri service enabled"
fi

# =============================================================================
#  PHASE 5 — Deploy Walled Garden Scripts
# =============================================================================
log "Phase 5: Deploy HIM-EDU Scripts"

# Clone from git or copy from /home/him/kolibri if available
mkdir -p "$INSTALL_DIR"

SOURCE_DIR="/home/${TARGET_USER}/kolibri"
if [ -d "$SOURCE_DIR/.git" ] || [ -f "$SOURCE_DIR/install.sh" ]; then
  log "Copying scripts from $SOURCE_DIR"
  # Copy scripts (not git internals or large data dirs)
  for f in start_ap.sh stop_ap.sh iptables_rules.sh server.py \
            him-ap.service him-firewall.service him-webserver.service \
            walled-garden.service dnsmasq.conf; do
    [ -f "$SOURCE_DIR/$f" ] && cp "$SOURCE_DIR/$f" "$INSTALL_DIR/$f"
  done
  [ -d "$SOURCE_DIR/www" ]   && cp -r "$SOURCE_DIR/www" "$INSTALL_DIR/"
  [ -d "$SOURCE_DIR/ssl" ]   && cp -r "$SOURCE_DIR/ssl" "$INSTALL_DIR/"
  ok "Scripts copied from $SOURCE_DIR"
else
  log "Writing scripts inline (no local repo found)..."
  _write_scripts
fi

chmod +x "$INSTALL_DIR/start_ap.sh" \
         "$INSTALL_DIR/stop_ap.sh" \
         "$INSTALL_DIR/iptables_rules.sh" \
         "$INSTALL_DIR/server.py" 2>/dev/null || true

# Write scripts inline if not present
write_script_if_missing() {
  local path="$1" content="$2"
  [ -f "$path" ] && return
  printf '%s\n' "$content" > "$path"
  chmod +x "$path"
}

# --- Detect and persist wireless interface -----------------------------------
log "Detecting wireless interface..."
IFACE=$(detect_wifi_iface) || { err "No wireless interface found — hotspot will not work."; IFACE=""; }
[ -n "$IFACE" ] && ok "Wireless interface: $IFACE (saved to $IFACE_CONF)"

# start_ap.sh
write_script_if_missing "$INSTALL_DIR/start_ap.sh" '#!/usr/bin/env bash
set -euo pipefail
SSID="him-edu"
PASSPHRASE="1234567890"
AP_IP="10.42.0.1"
DHCP_RANGE="10.42.0.10,10.42.0.254,255.255.255.0,12h"
COUNTRY="US"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IFACE_CONF="${SCRIPT_DIR}/wifi-iface.conf"
[ "$(id -u)" -ne 0 ] && { echo "Run as root" >&2; exit 2; }

# Universal interface detection — tries saved value first, then all methods
detect_iface() {
  # 1. Saved value
  if [ -f "$IFACE_CONF" ]; then
    local s; s=$(cat "$IFACE_CONF")
    [ -n "$s" ] && [ -d "/sys/class/net/$s" ] && { echo "$s"; return 0; }
  fi
  # 2. iw dev (works for wlan0, wlp*, wlx<mac>, etc.)
  local i
  i=$(iw dev 2>/dev/null | awk "/Interface/{print \$2}" | head -1)
  [ -n "$i" ] && { echo "$i"; return 0; }
  # 3. phy80211 symlink — catches any wireless NIC regardless of name
  for dev in /sys/class/net/*/phy80211; do
    [ -e "$dev" ] && { basename "$(dirname "$dev")"; return 0; }
  done
  # 4. Name-pattern fallback
  ls /sys/class/net/ 2>/dev/null | grep -E "^wl" | head -1
}

IFACE=$(detect_iface)
[ -z "$IFACE" ] && { echo "No wireless interface found" >&2; exit 1; }
echo "Using wireless interface: $IFACE"

pkill hostapd 2>/dev/null || true
pkill dnsmasq 2>/dev/null || true
pkill -f "python3 ${SCRIPT_DIR}/server.py" 2>/dev/null || true
sleep 1
nmcli device set "$IFACE" managed no 2>/dev/null || true
sleep 1
ip link set "$IFACE" down 2>/dev/null || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "${AP_IP}/24" dev "$IFACE"
ip link set "$IFACE" up
sleep 1
cat > "${SCRIPT_DIR}/hostapd.conf" <<EOF
interface=${IFACE}
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=6
ieee80211n=1
auth_algs=1
wpa=2
wpa_passphrase=${PASSPHRASE}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
country_code=${COUNTRY}
ieee80211d=1
EOF
cat > "${SCRIPT_DIR}/dnsmasq.conf" <<EOF
interface=${IFACE}
bind-interfaces
except-interface=lo
listen-address=${AP_IP}
dhcp-range=${DHCP_RANGE}
dhcp-option=3,${AP_IP}
dhcp-option=6,${AP_IP}
address=/#/${AP_IP}
log-queries
log-dhcp
EOF
hostapd -B "${SCRIPT_DIR}/hostapd.conf"
sleep 2
dnsmasq --conf-file="${SCRIPT_DIR}/dnsmasq.conf" --pid-file=/run/him-dnsmasq.pid
"${SCRIPT_DIR}/iptables_rules.sh" apply "$IFACE" "$AP_IP"
pgrep -f "python3 ${SCRIPT_DIR}/server.py" >/dev/null || \
  nohup python3 "${SCRIPT_DIR}/server.py" >"${SCRIPT_DIR}/server.log" 2>&1 &
echo "HIM Education Walled Garden ACTIVE — SSID: $SSID / Portal: http://${AP_IP}/"'

# stop_ap.sh
write_script_if_missing "$INSTALL_DIR/stop_ap.sh" '#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IFACE_CONF="${SCRIPT_DIR}/wifi-iface.conf"
[ "$(id -u)" -ne 0 ] && { echo "Run as root" >&2; exit 2; }

detect_iface() {
  [ -f "$IFACE_CONF" ] && local s; s=$(cat "$IFACE_CONF" 2>/dev/null)
  [ -n "$s" ] && [ -d "/sys/class/net/$s" ] && { echo "$s"; return 0; }
  iw dev 2>/dev/null | awk "/Interface/{print \$2}" | head -1 && return 0
  for dev in /sys/class/net/*/phy80211; do
    [ -e "$dev" ] && { basename "$(dirname "$dev")"; return 0; }
  done
  ls /sys/class/net/ 2>/dev/null | grep -E "^wl" | head -1
}

IFACE=$(detect_iface)
pkill -f "python3 ${SCRIPT_DIR}/server.py" || true
pkill hostapd || true
[ -f /run/him-dnsmasq.pid ] && kill "$(cat /run/him-dnsmasq.pid)" 2>/dev/null || pkill dnsmasq 2>/dev/null || true
rm -f /run/him-dnsmasq.pid
"${SCRIPT_DIR}/iptables_rules.sh" clear
[ -n "$IFACE" ] && { ip addr flush dev "$IFACE" 2>/dev/null; nmcli device set "$IFACE" managed yes 2>/dev/null; } || true
echo "Walled garden stopped."'

# iptables_rules.sh
write_script_if_missing "$INSTALL_DIR/iptables_rules.sh" '#!/usr/bin/env bash
set -euo pipefail
ACTION="${1:-apply}"
IFACE="${2:-}"
AP_IP="${3:-10.42.0.1}"
IFACE_CONF="/opt/him-edu/wifi-iface.conf"
[ "$(id -u)" -ne 0 ] && { echo "Run as root" >&2; exit 2; }
if [ "$ACTION" = "clear" ]; then
  iptables -t nat -F 2>/dev/null || true
  iptables -F FORWARD 2>/dev/null || true
  iptables -P FORWARD ACCEPT 2>/dev/null || true
  echo "iptables cleared."
  exit 0
fi
# Resolve interface: arg > saved file > auto-detect
if [ -z "$IFACE" ]; then
  [ -f "$IFACE_CONF" ] && IFACE=$(cat "$IFACE_CONF")
fi
if [ -z "$IFACE" ]; then
  IFACE=$(iw dev 2>/dev/null | awk "/Interface/{print \$2}" | head -1)
fi
if [ -z "$IFACE" ]; then
  for dev in /sys/class/net/*/phy80211; do
    [ -e "$dev" ] && IFACE=$(basename "$(dirname "$dev")") && break
  done
fi
[ -z "$IFACE" ] && IFACE=$(ls /sys/class/net/ 2>/dev/null | grep -E "^wl" | head -1)
[ -z "$IFACE" ] && { echo "No wireless interface" >&2; exit 1; }
iptables -t nat -F
iptables -F FORWARD
iptables -P FORWARD DROP
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 53 -j DNAT --to-destination "${AP_IP}:53"
iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport 53 -j DNAT --to-destination "${AP_IP}:53"
iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport 80  -j DNAT --to-destination "${AP_IP}:80"
iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport 443 -j DNAT --to-destination "${AP_IP}:443"
echo "Walled garden iptables applied on $IFACE (portal: $AP_IP)"'

# server.py
write_script_if_missing "$INSTALL_DIR/server.py" '#!/usr/bin/env python3
"""HIM Education captive portal server — HTTP :80 and HTTPS :443."""
import os, sys, ssl, threading, subprocess
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
ThreadingHTTPServer.allow_reuse_address = True
ROOT = os.path.dirname(os.path.abspath(__file__))
WWW_DIR = os.path.join(ROOT, "www")
CERT_DIR = os.path.join(ROOT, "ssl")
CERT_PEM = os.path.join(CERT_DIR, "cert.pem")
KEY_PEM  = os.path.join(CERT_DIR, "key.pem")
INDEX_BYTES = b""
def load_index():
    with open(os.path.join(WWW_DIR, "index.html"), "rb") as f: return f.read()
class Handler(BaseHTTPRequestHandler):
    def _serve(self):
        self.send_response(200); self.send_header("Content-Type","text/html; charset=utf-8")
        self.send_header("Cache-Control","no-store"); self.end_headers(); self.wfile.write(INDEX_BYTES)
    do_GET = do_POST = _serve
    def do_HEAD(self):
        self.send_response(200); self.send_header("Content-Type","text/html"); self.end_headers()
    def log_message(self, fmt, *a): sys.stderr.write("%s %s\n" % (self.address_string(), fmt%a))
def ensure_cert(host="10.42.0.1"):
    if os.path.exists(CERT_PEM) and os.path.exists(KEY_PEM): return
    os.makedirs(CERT_DIR, exist_ok=True)
    subprocess.check_call(["openssl","req","-x509","-nodes","-days","3650",
        "-newkey","rsa:2048","-keyout",KEY_PEM,"-out",CERT_PEM,"-subj",f"/CN={host}"])
def run_http():
    s = ThreadingHTTPServer(("",80), Handler); print("HTTP :80"); s.serve_forever()
def run_https():
    ensure_cert()
    if not (os.path.exists(CERT_PEM) and os.path.exists(KEY_PEM)): return
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(CERT_PEM, KEY_PEM)
    s = ThreadingHTTPServer(("",443), Handler); s.socket = ctx.wrap_socket(s.socket, server_side=True)
    print("HTTPS :443"); s.serve_forever()
def main():
    global INDEX_BYTES
    if os.geteuid() != 0: sys.exit("Run as root")
    INDEX_BYTES = load_index()
    threading.Thread(target=run_http,  daemon=True).start()
    threading.Thread(target=run_https, daemon=True).start()
    try: threading.Event().wait()
    except KeyboardInterrupt: pass
if __name__ == "__main__": main()'

# www/index.html
mkdir -p "$INSTALL_DIR/www"
if [ ! -f "$INSTALL_DIR/www/index.html" ]; then
cat > "$INSTALL_DIR/www/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>HIM Education</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
      background:#eef2f7;color:#333;min-height:100vh;display:flex;align-items:center;
      justify-content:center;padding:20px}
    .container{max-width:560px;width:100%;background:#fff;border-radius:12px;
      box-shadow:0 8px 30px rgba(0,0,0,.10);padding:40px 32px;text-align:center}
    .logo{font-size:2.2em;font-weight:700;color:#0056b3;margin-bottom:6px}
    .subtitle{font-size:1em;color:#666;margin-bottom:28px}
    .welcome{font-size:1.05em;color:#444;margin-bottom:30px;line-height:1.6}
    .services{display:flex;flex-direction:column;gap:14px;margin-bottom:28px}
    .btn{display:block;padding:16px 24px;border-radius:8px;text-decoration:none;
      font-size:1.15em;font-weight:600;color:#fff;transition:transform .15s,box-shadow .15s}
    .btn:hover{transform:translateY(-2px);box-shadow:0 4px 14px rgba(0,0,0,.18)}
    .btn-kolibri{background:#0078d4}.btn-kolibri:hover{background:#005ea6}
    .btn-nextcloud{background:#0082c9}.btn-nextcloud:hover{background:#00669e}
    .desc{font-size:.85em;color:#888;margin-top:2px;font-weight:400}
    .footer{font-size:.82em;color:#999;border-top:1px solid #eee;padding-top:18px}
  </style>
</head>
<body>
  <div class="container">
    <div class="logo">HIM Education</div>
    <div class="subtitle">Local Learning Portal</div>
    <p class="welcome">Welcome! You are connected to the HIM Education offline learning network.
      Choose a service below to get started.</p>
    <div class="services">
      <a class="btn btn-kolibri" href="http://10.42.0.1:8080/">
        Kolibri — Learning Platform
        <div class="desc">Interactive lessons, videos &amp; exercises</div>
      </a>
      <a class="btn btn-nextcloud" href="http://10.42.0.1:8081/">
        NextCloud — File Sharing
        <div class="desc">Documents, resources &amp; collaboration</div>
      </a>
    </div>
    <div class="footer">HIM Education &mdash; him-edu Wi-Fi Network</div>
  </div>
</body>
</html>
HTMLEOF
  ok "Landing page written"
fi

# =============================================================================
#  PHASE 6 — NextCloud Docker Stack
# =============================================================================
log "Phase 6: NextCloud Docker Stack"

mkdir -p "$NEXTCLOUD_DIR"/{html,custom_apps,config,data,nextclouddb,redis,npm-data,letsencrypt}

# Write docker-compose.yml
cat > "$NEXTCLOUD_DIR/docker-compose.yml" <<'COMPOSEEOF'
version: '3'

services:
  nextcloud:
    image: nextcloud
    container_name: nextcloud
    restart: unless-stopped
    networks:
      - cloud
    depends_on:
      - nextclouddb
      - redis
    ports:
      - "8081:80"
    volumes:
      - ./html:/var/www/html
      - ./custom_apps:/var/www/html/custom_apps
      - ./config:/var/www/html/config
      - ./data:/var/www/html/data
    environment:
      - TZ=America/Los_Angeles
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD=dbpassword
      - MYSQL_HOST=nextclouddb
      - REDIS_HOST=redis

  nextclouddb:
    image: mariadb
    container_name: nextcloud-db
    restart: unless-stopped
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW
    networks:
      - cloud
    volumes:
      - ./nextclouddb:/var/lib/mysql
    environment:
      - TZ=America/Los_Angeles
      - MYSQL_RANDOM_ROOT_PASSWORD=true
      - MYSQL_PASSWORD=dbpassword
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud

  collabora:
    image: collabora/code
    container_name: collabora
    restart: unless-stopped
    cap_add:
      - MKNOD
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    networks:
      - cloud
    environment:
      - TZ=America/Los_Angeles
      - password=password
      - username=nextcloud
      - domain=10\\.42\\.0\\.1|nextcloud
      - server_name=10.42.0.1:9980
      - extra_params=--o:ssl.enable=false --o:ssl.termination=false
    ports:
      - "9980:9980"

  redis:
    image: redis:alpine
    container_name: redis
    restart: unless-stopped
    networks:
      - cloud
    volumes:
      - ./redis:/data

  nginx-proxy:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy
    restart: unless-stopped
    environment:
      - TZ=America/Los_Angeles
    ports:
      - "81:81"
    volumes:
      - ./npm-data:/data
      - ./letsencrypt:/etc/letsencrypt
    networks:
      - cloud

networks:
  cloud:
    name: cloud
    driver: bridge
COMPOSEEOF
ok "docker-compose.yml written to $NEXTCLOUD_DIR"

# Start containers
log "Starting NextCloud Docker stack..."
cd "$NEXTCLOUD_DIR"
docker compose down 2>/dev/null || true
docker compose up -d
ok "Containers started"

# Wait for NextCloud
log "Waiting for NextCloud to be ready (up to 90s)..."
for i in $(seq 1 90); do
  docker inspect --format='{{.State.Running}}' nextcloud 2>/dev/null | grep -q true && break
  sleep 1
done

# Wait for MariaDB
log "Waiting for MariaDB (up to 120s)..."
for i in $(seq 1 60); do
  docker exec nextcloud-db mariadb -u nextcloud -pdbpassword -e "SELECT 1" >/dev/null 2>&1 && break
  sleep 2
done

sleep 5

# Initial NextCloud setup if not already installed
INSTALLED=$(docker exec -u www-data nextcloud php occ status --output=json 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('installed',False))" 2>/dev/null || echo "False")

if [ "$INSTALLED" = "True" ]; then
  ok "NextCloud already installed"
else
  log "Running NextCloud initial setup..."
  docker exec -u www-data nextcloud php occ maintenance:install \
    --database "mysql" \
    --database-host "nextclouddb" \
    --database-name "nextcloud" \
    --database-user "nextcloud" \
    --database-pass "dbpassword" \
    --admin-user "admin" \
    --admin-pass "admin123"
  ok "NextCloud installed (admin / admin123)"
fi

# Configure trusted domains and settings
docker exec -u www-data nextcloud php occ config:system:set trusted_domains 1 --value="${AP_IP}:8081"
docker exec -u www-data nextcloud php occ config:system:set trusted_domains 2 --value="${AP_IP}"
docker exec -u www-data nextcloud php occ config:system:set overwrite.cli.url --value="http://${AP_IP}:8081"
docker exec -u www-data nextcloud php occ config:system:set overwriteprotocol --value="http"
docker exec -u www-data nextcloud php occ config:system:set allow_local_remote_servers --type boolean --value true
docker exec -u www-data nextcloud php occ config:system:set has_internet_connection --type boolean --value true
ok "NextCloud configured"

# =============================================================================
#  PHASE 7 — NextCloud Apps
# =============================================================================
log "Phase 7: NextCloud Apps"

CALENDAR_VER="6.2.1"
NOTES_VER="4.13.0"
RICHDOCS_VER="10.1.0"

install_nc_app() {
  local app_id="$1" app_ver="$2" app_url="$3"
  if docker exec -u www-data nextcloud php occ app:list --enabled 2>/dev/null \
      | grep -q "  - ${app_id}:"; then
    ok "$app_id already enabled"
    return
  fi
  log "Installing $app_id v$app_ver..."
  docker exec nextcloud bash -c "
    cd /tmp &&
    curl -fsSL -o ${app_id}.tar.gz ${app_url} &&
    tar xzf ${app_id}.tar.gz -C /var/www/html/custom_apps/ &&
    chown -R www-data:www-data /var/www/html/custom_apps/${app_id} &&
    rm -f ${app_id}.tar.gz"
  docker exec -u www-data nextcloud php occ app:enable "$app_id"
  ok "$app_id v$app_ver installed"
}

install_nc_app "calendar" "$CALENDAR_VER" \
  "https://github.com/nextcloud-releases/calendar/releases/download/v${CALENDAR_VER}/calendar-v${CALENDAR_VER}.tar.gz"

install_nc_app "notes" "$NOTES_VER" \
  "https://github.com/nextcloud-releases/notes/releases/download/v${NOTES_VER}/notes-v${NOTES_VER}.tar.gz"

install_nc_app "richdocuments" "$RICHDOCS_VER" \
  "https://github.com/nextcloud-releases/richdocuments/releases/download/v${RICHDOCS_VER}/richdocuments-v${RICHDOCS_VER}.tar.gz"

# Collabora WOPI
docker exec -u www-data nextcloud php occ config:app:set richdocuments wopi_url --value="http://collabora:9980"
docker exec -u www-data nextcloud php occ config:app:set richdocuments public_wopi_url --value="http://${AP_IP}:9980"
docker exec -u www-data nextcloud php occ config:app:set richdocuments wopi_allowlist --value="10.42.0.0/24,172.18.0.0/16"
ok "Collabora WOPI configured"

# =============================================================================
#  PHASE 8 — Systemd Services
# =============================================================================
log "Phase 8: Systemd Services"

# him-ap.service — uses start_ap.sh which has full universal detection built in
cat > /etc/systemd/system/him-ap.service <<EOF
[Unit]
Description=HIM Education Wi-Fi Access Point
After=network.target
Before=him-firewall.service him-webserver.service

[Service]
Type=forking
PIDFile=/run/hostapd.pid
# Delegate all interface detection to start_ap.sh (universal, reads saved iface)
ExecStart=/bin/bash ${INSTALL_DIR}/start_ap.sh
ExecStop=/bin/bash ${INSTALL_DIR}/stop_ap.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# him-firewall.service
cat > /etc/systemd/system/him-firewall.service <<EOF
[Unit]
Description=HIM Education Walled Garden Firewall
After=network.target him-ap.service
Before=him-webserver.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash ${INSTALL_DIR}/iptables_rules.sh apply
ExecStop=/bin/bash ${INSTALL_DIR}/iptables_rules.sh clear

[Install]
WantedBy=multi-user.target
EOF

# him-webserver.service
cat > /etc/systemd/system/him-webserver.service <<EOF
[Unit]
Description=HIM Education Captive Portal Web Server
After=network.target him-ap.service him-firewall.service
Wants=him-ap.service him-firewall.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/server.py
WorkingDirectory=${INSTALL_DIR}
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

# walled-garden.service (all-in-one)
cat > /etc/systemd/system/walled-garden.service <<EOF
[Unit]
Description=HIM Education Walled Garden (all-in-one)
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${INSTALL_DIR}/start_ap.sh
ExecStop=${INSTALL_DIR}/stop_ap.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable him-ap.service him-firewall.service him-webserver.service
ok "Systemd services installed and enabled"

# =============================================================================
#  PHASE 9 — Start Walled Garden
# =============================================================================
log "Phase 9: Starting Walled Garden"

if systemctl is-active --quiet him-ap.service 2>/dev/null; then
  ok "Walled garden already running"
else
  systemctl start him-ap.service him-firewall.service him-webserver.service || \
    bash "$INSTALL_DIR/start_ap.sh" &
  ok "Walled garden started"
fi

# Persist iptables rules so they survive reboot
log "Persisting iptables rules..."
if cmd_exists netfilter-persistent; then
  netfilter-persistent save
  ok "iptables rules saved (netfilter-persistent)"
elif cmd_exists iptables-save; then
  mkdir -p /etc/iptables
  iptables-save  > /etc/iptables/rules.v4
  ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
  # Restore on boot via rc.local if iptables-persistent not available
  if ! cmd_exists netfilter-persistent; then
    cat > /etc/rc.local <<'RCEOF'
#!/bin/bash
iptables-restore < /etc/iptables/rules.v4
exit 0
RCEOF
    chmod +x /etc/rc.local
    systemctl enable rc-local 2>/dev/null || true
  fi
  ok "iptables rules saved to /etc/iptables/rules.v4"
fi

# =============================================================================
#  PHASE 10 — Kolibri Channels (English + Español)
# =============================================================================
log "Phase 10: Kolibri Channels"

# Kolibri must be running to import content
if ! systemctl is-active --quiet kolibri 2>/dev/null; then
  systemctl start kolibri 2>/dev/null || true
  sleep 5
fi

# Kolibri runs as the 'kolibri' user — detect its home/data dir
KOLIBRI_HOME=$(getent passwd kolibri 2>/dev/null | cut -d: -f6 || echo "/var/kolibri")
export KOLIBRI_HOME

import_kolibri_channel() {
  local name="$1" cid="$2"
  log "Importing Kolibri channel: $name ($cid)"

  # Check if channel already imported
  if sudo -u kolibri kolibri manage listchannels 2>/dev/null | grep -qi "$cid"; then
    ok "$name already imported"
    return 0
  fi

  # Import channel metadata (fast — just the catalog/tree)
  if sudo -u kolibri kolibri manage importchannel network "$cid" 2>&1; then
    ok "$name channel metadata imported"
  else
    warn "$name channel metadata import failed — no internet or channel ID changed"
    warn "Import manually later: sudo -u kolibri kolibri manage importchannel network $cid"
    return 1
  fi

  # Import all content (can be large — GBs; runs in background)
  log "Downloading $name content (this runs in background — may take hours)..."
  nohup sudo -u kolibri kolibri manage importcontent network "$cid" \
    >> "$LOG_FILE" 2>&1 &
  ok "$name content download started (PID $!) — check $LOG_FILE for progress"
}

# Full channel list — 60 channels (English + Español)
KOLIBRI_CHANNELS=(
  # English channels
  "8a2d480dbc9b53408c688e8188326b16|Aflatoun Academy (en)"
  "d0ef6f71e4fe4e54bb87d7dab5eeaae2|Be Strong: Internet Safety"
  "e409b964366a59219c148f2aaa741f43|Blockly Games"
  "2d7b056d668a58ee9244ccf76108cbdb|Book Dash"
  "922e9c576c2f59e59389142b136308ff|Career Girls"
  "d35a806594a843f2864457eac34ee12e|Childhood Education International"
  "1d8f6d84618153c18c695d85074952a7|CK-12 (English)"
  "cf4fee6d062a49fc88131f8a4ea2192e|Colors of Kindness"
  "bbb4ea407a3c450cb18cbaa76f2d75cd|CSpathshala (English)"
  "9b3463eaa85354eeb26a184fe1d9a04b|Digital Awareness (English)"
  "63e8e65976f258cf9b1a5bb85e486aa8|Digital Discovery (English)"
  "c51a0f842fed427c95acff9bb4a21e3c|EENET Inclusive Education"
  "d6e3b856125f5e6aa5fb40c8b112d5e9|EngageNY (English)"
  "61b75af2bb2c4c0ea850d85dcf88d0fd|Espresso English"
  "0418cc231e9c5513af0fff9f227f7172|Free English with Hello Channel"
  "0e173fca6e9052f8a474a2fb84055faf|Global Digital Library"
  "5d53b37cc90e50128a40e293d9fadb27|Global Youth Communities"
  "b62c5c2139a65fb2aaf68987a25b28a1|Goalkicker Tech Books"
  "624e09bb5eeb4d20aa8de62e7b4778a0|How to Get Started with Kolibri"
  "7ec3b2ad48925d639592954e2298618f|HP LIFE Courses (English)"
  "c9d7f950ab6b5a1199e3d6c10d7f0103|Khan Academy (English - US)"
  "6616efc8aa604a308c8f5d18b00a1ce3|Khan Academy - Standardized Test Prep"
  "913efe9f14c65cb1b23402f21f056e99|MIT Blossoms"
  "3c77d9dd717341bb8fff8da6ab980df3|Mother Goose Club Video Lessons"
  "4dd2e97a930851579b92add96d2e81f7|Nal'ibali Web Resource Tree"
  "fc47aee82e0153e2a30197d3fdee1128|Open Stax"
  "8b28761bac075deeb66adc6c80ef119c|Osmosis.org"
  "b8bd7770063d40a8bd9b30d4703927b5|PBS SoCal: Family Math"
  "197934f144305350b5820c7c4dd8e194|PhET Interactive Simulations (English)"
  "131e543dbecf5776bb13cfcfddf05605|Pratham Books StoryWeaver"
  "f758ac6ad39c452f956658da6ad7d3cc|Project Based Learning with Kolibri"
  "305b12ea5ea84fa18f933705c23f5ee0|School of Thought"
  "f189d7c505644311a4e62d9f3259e31b|Sciensation"
  "3e464ee12f6a50a781cddf59147b48b1|Sikana (English)"
  "12cee68c112452a1be3f73e730ec2114|Stanford Digital MEdIC Coronavirus Toolkit"
  "8db463b116d24a6c8f56c4df4fa88041|Tackling Violence Film Series"
  "1e378725d3924b47aa5e1260628820b5|TED-Ed Lessons"
  "a9b25ac9814742c883ce1b0579448337|TESSA Teacher Resources"
  "74f36493bb475b62935fa8705ed59fed|Thoughtful Learning"
  "000409f81dbe5d1ba67101cb9fed4530|Touchable Earth (English)"
  "ec29f4cc20a8437d844a60297c2ffd07|Using Studio: Kolibri Content Workspace"
  # Español channels
  "fed29d60e4d84a1e8dcfc781d920b40e|Biblioteca Elejandria"
  "1c98e92b8c2f536796960bed8d137a25|Ceibal"
  "da53f90b1be25752a04682bbc353659f|Ciencia NASA (Español)"
  "07cd1633691b4473b6fda08caf826253|Ciensación"
  "c984c3f6cec55ecc997769213e5a855d|CK-12 (Español)"
  "e0bba57cf3475efbbafc3623c4ea6332|CommonLit (Español)"
  "604ad3b85d844dd89ee70fa12a9a5a6e|CREE+"
  "7e68bc59d4304e718a0750b1b87125ad|Cultura Emprendedora"
  "31be5e9773ba4fbc96e04ff9228681ec|Educación Internacional Infantil"
  "a12aa60789ab5b11b7f0b87bafe093e5|EngageNY (Español)"
  "0a3446937e3340fa86e6010ba80e16e1|Guía de Alfabetización Digital Crítica"
  "d0cb2b465843584e9c72969ea5ea5519|HP LIFE Cursos (Español)"
  "c1f2b7e6ac9f56a2bb44fa7a48b66dce|Khan Academy (Español)"
  "f6cb302ef6594db4b4a04b4991a595c2|Plan Educativo TIC Basico"
  "f446655247a95c0aa94ca9fa4d66783b|Proyecto Biosfera"
  "c4ad70f67dff57738591086e466f9afc|Proyecto Descartes"
  "8fa678af1dd05329bf3218c549b84996|Simulaciones interactivas PhET"
  "30c71c99c42c57d181e8aeafd2e15e5f|Sikana (Español)"
  "b06dd546e8ba4b44bf921862c9948ffe|WiiXii"
)

if curl -fsS --max-time 10 https://kolibri-studio.learningequality.org >/dev/null 2>&1; then
  log "Internet available — importing ${#KOLIBRI_CHANNELS[@]} Kolibri channels..."
  for entry in "${KOLIBRI_CHANNELS[@]}"; do
    cid="${entry%%|*}"
    name="${entry##*|}"
    import_kolibri_channel "$name" "$cid"
  done
  ok "All Kolibri channel imports initiated (content downloads continue in background)"
else
  warn "No internet access — Kolibri channels cannot be downloaded now."
  warn "Once online, run: sudo bash /opt/him-edu/provision.sh"
  warn "  OR import manually:"
  for entry in "${KOLIBRI_CHANNELS[@]}"; do
    cid="${entry%%|*}"
    name="${entry##*|}"
    warn "  sudo -u kolibri kolibri manage importchannel network $cid  # $name"
  done
fi

# =============================================================================
#  DONE
# =============================================================================
echo ""
echo "========================================================="
echo "  HIM Education Server provisioning COMPLETE"
echo "========================================================="
echo "  Hostname:   $(hostname)"
echo "  Wi-Fi SSID: $SSID  |  Password: $PASSPHRASE"
echo "  Portal:     http://${AP_IP}/"
echo "  Kolibri:    http://${AP_IP}:8080/"
echo "  NextCloud:  http://${AP_IP}:8081/"
echo "  NC Admin:   admin / admin123"
echo "  Tailscale:  run 'tailscale up' to authenticate"
echo "  Channels:   60 channels EN + ES (downloading in background)"
echo "  Log:        $LOG_FILE"
echo "========================================================="
echo "=== HIM Provision finished: $(date) ==="
